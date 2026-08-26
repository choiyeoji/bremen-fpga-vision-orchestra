# 🎵 브레멘 음악대 (The Bremen Town Musicians)

> 6대의 OV7670 카메라와 다중 FPGA를 이용한 **실시간 비전 연주 시스템**  
> 대한상공회의소 서울기술교육센터 | 2026.07.01 ~ 2026.07.21

<br>

## 📌 프로젝트 개요

**브레멘 음악대**는 1대의 Master FPGA와 5대의 Slave FPGA를 이용해 6대의 OV7670 영상을 실시간으로 처리하고, 객체 위치를 음계 데이터로 변환하여 연주하는 6인 팀 프로젝트입니다.

Slave FPGA의 영상은 SPI를 통해 Master FPGA로 전달되고, Master에서는 영상을 2×3 VGA 화면으로 통합합니다. 음계 데이터는 별도의 통신 경로를 통해 수집하여 PC의 오디오 프로그램과 연동했습니다.

<p align="center">
  <img src="./images/top_bd.png" width="800">
</p>

<p align="center">
  <b>전체 시스템 구성</b>
</p>

> **이 README는 팀 전체 기능 중 제가 담당한 `Ping-Pong Buffer 기반 영상 메모리 제어`를 중심으로 정리했습니다.**  
> YCoCg 압축, I2C/UART 통신, 객체 검출 및 UVM 검증 등 다른 팀원의 상세 구현은 전체 시스템 구성 요소로만 소개합니다.

<br>

## 👥 팀 구성 및 역할

| 이름 | 담당 역할 |
| :---: | --- |
| 이준형 | Master Integration, 전체 시스템 아키텍처 및 화면 병합 |
| 곽은찬 | Python 영상/오디오 UI 및 UART 통신 |
| 안정현 | I2C Master/Slave 프로토콜 및 FSM |
| 윤지원 | YCoCg 영상 압축·복원 |
| **최여지** | **Ping-Pong Buffer 기반 메모리 컨트롤러 및 동기화** |
| 최은수 | Slave Integration, OV7670 제어 및 객체 인식 |

<br>

## 🙋 담당 역할

### Ping-Pong Buffer 기반 영상 메모리 제어

- Slave FPGA 영상 저장용 Memory A/B 구조 구성
- 한 메모리에 카메라 영상을 저장하는 동안 다른 메모리를 SPI 전송용으로 사용
- `frame_done`과 전송 상태를 기준으로 Write/Read Buffer 전환 시점 제어
- SPI 전송 중인 메모리가 새로운 Frame으로 덮어써지지 않도록 접근 충돌 방지
- Frame 단위 Buffer 전환 및 영상 데이터 흐름 검증

<br>

## 🛠 사용 기술

| 구분 | 사용 기술 |
| --- | --- |
| HDL / FPGA | SystemVerilog, Basys 3, Xilinx Artix-7 |
| Memory | Dual Buffer, Ping-Pong Buffer, FPGA Memory |
| Video | OV7670, Frame-based Image Data |
| Communication | SPI 연동 |
| Tool | Vivado 2020.2 |

<br>

# ⚙️ 담당 데이터 흐름

Slave FPGA에서는 카메라 영상 데이터를 메모리에 저장한 뒤 SPI 전송 단계에서 읽어 사용합니다.

```text
OV7670 Camera
      ↓
Downscale Image
      ↓
Cam_WriteController
      ↓
┌──────────────────────┐
│  Memory A / Memory B │
│   Ping-Pong Buffer   │
└──────────────────────┘
      ↓
Frame Sender
      ↓
SPI → Master FPGA
```

핵심은 **영상 저장과 SPI 전송이 동일한 메모리에 동시에 접근하지 않도록 Memory A/B의 역할을 교차시키는 것**입니다.

<br>

# 💾 Ping-Pong Buffer 구조

`Cam_frameBuffer.sv`에서는 두 개의 영상 메모리 `mem0`, `mem1`을 사용합니다.

```text
Frame N
Camera Write → Memory A
SPI Read     → Memory B

Frame Complete
       ↓
Buffer Swap

Frame N+1
Camera Write → Memory B
SPI Read     → Memory A
```

현재 Write Buffer를 `w_sel`로 선택하고, Read 데이터는 Write Buffer와 반대쪽 Memory에서 가져오도록 구성했습니다.

```text
w_sel = 0 → Write mem0 / Read mem1
w_sel = 1 → Write mem1 / Read mem0
```

이 구조를 통해 새로운 영상이 저장되는 동안 이전 Frame을 SPI 전송에 사용할 수 있도록 했습니다.

관련 RTL:

```text
src/slave/rtl/Cam_frameBuffer.sv
```

<br>

## Frame 완료 및 Buffer 전환

카메라 영상의 Frame 완료 시점은 `Cam_WriteController.sv`에서 생성되는 `frame_done` 신호로 확인합니다.

`Cam_frameBuffer.sv`에서는 다음 조건에서 Buffer를 전환합니다.

```text
frame_done && !tx_busy
```

여기서 전송 상태는 다음과 같이 구성되어 있습니다.

```text
tx_busy = sending | sender_busy
```

따라서 **Frame 저장이 끝났더라도 SPI 전송이 진행 중이면 Buffer를 즉시 바꾸지 않고**, 전송이 끝난 상태에서만 `w_sel`을 반전시킵니다.

관련 RTL:

```text
src/slave/rtl/Cam_WriteController.sv
src/slave/rtl/Cam_frameBuffer.sv
```

<br>

# ⚠️ 문제 해결

## 영상 저장과 SPI 전송 간 메모리 충돌

### 문제

카메라 영상 저장과 SPI 전송이 같은 메모리에서 동시에 수행될 경우, 전송 중인 Frame이 새로운 영상 데이터로 덮어써질 수 있었습니다.

### 해결

- 영상 저장용 Memory와 SPI Read용 Memory를 A/B로 분리
- `frame_done`으로 Frame 저장 완료 시점 확인
- `sending`, `sender_busy`를 이용해 SPI 전송 상태 확인
- 전송 중에는 Buffer 전환을 금지하고, 전송이 끝난 상태에서만 `w_sel` 반전
- SPI 전송 완료 시 `frame_ready` 상태를 정리하여 다음 Frame 처리 준비

### 결과

영상 저장과 SPI 전송이 서로 다른 Memory에서 수행되도록 분리하여 Read/Write 충돌을 방지하고, Frame 단위의 안정적인 영상 전달 흐름을 구성했습니다.

<br>

# 🧪 검증 내용

담당한 메모리 제어 구간을 중심으로 다음 동작을 확인했습니다.

- 영상 저장 시 Write Address 증가 동작 확인
- Frame 완료 시 `frame_done` 발생 확인
- Memory A/B가 Frame 단위로 교차 선택되는지 확인
- SPI 전송 중 Buffer가 변경되지 않는지 확인
- 전송 중인 Memory에 새로운 영상이 덮어써지지 않는지 확인
- 최종 시스템에서 6개 영상의 2×3 VGA 통합 결과 확인

<p align="center">
  <img src="./images/VGA_teamproj.gif" width="800">
</p>

<p align="center">
  <b>다중 FPGA 영상 통합 결과</b>
</p>

<br>

# 🎥 시연 영상

<p align="center">
  <a href="https://youtu.be/NtwXzo_WktU">
    <img src="./images/play.png" width="800">
  </a>
</p>

<p align="center">
  <i>이미지를 클릭하면 전체 시스템 시연 영상을 확인할 수 있습니다.</i>
</p>

<br>

# 📂 담당 내용 관련 코드

전체 Repository에는 Master/Slave FPGA의 팀 통합 소스가 포함되어 있습니다. 아래 파일은 이 README에서 설명한 **Slave 영상 메모리 저장 및 Ping-Pong Buffer 제어**와 직접 연결된 코드입니다.

```text
src/slave/rtl/
├── Cam_WriteController.sv
├── Cam_frameBuffer.sv
├── frame_sender.sv
└── top_VGA.sv
```

| 파일 | 역할 |
| --- | --- |
| `Cam_WriteController.sv` | 영상 Write Address 및 Frame 완료 시점 생성 |
| `Cam_frameBuffer.sv` | Memory A/B 저장, Read 선택 및 Buffer 전환 제어 |
| `frame_sender.sv` | 저장된 Frame의 SPI 전송 경로 연동 |
| `top_VGA.sv` | Memory Control과 Frame Sender의 시스템 연결 |

> Repository의 I2C, UART, YCoCg, 객체 검출, Master Integration 및 UVM 관련 코드는 팀 전체 프로젝트의 통합 소스입니다.

<br>

## 📄 발표 자료

전체 시스템 구성과 팀 프로젝트 결과는 아래 발표 자료에서 확인할 수 있습니다.

<p align="center">
  <a href="./docs/260721_bremen_musicians.pdf">
    <b>📑 프로젝트 발표 자료 보기</b>
  </a>
</p>

<br>

## 💡 프로젝트를 통해 배운 점

- 실시간 영상 처리에서 Read/Write 메모리 접근 시점을 분리하는 방법을 경험했습니다.
- Ping-Pong Buffer를 이용해 영상 저장과 전송을 병렬로 처리하는 구조를 이해했습니다.
- Frame 완료 상태와 SPI 전송 상태를 함께 확인하여 Buffer 전환 시점을 제어했습니다.
- 개별 모듈의 동작뿐 아니라 영상 저장 → 메모리 전환 → SPI 전송으로 이어지는 데이터 흐름을 확인하는 과정의 중요성을 배웠습니다.

---

*Ping-Pong Buffer 기반 영상 메모리 제어를 중심으로 정리한 프로젝트 Repository입니다.*