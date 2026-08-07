# 🎵 브레멘 음악대 (The Bremen Town Musicians)

> 카메라와 FPGA가 함께 꿈을 이루는 실시간 비전(Vision) 연주 시스템  
> 대한상공회의소 서울기술교육센터 | 2026.07.21

---

## 📌 프로젝트 개요

**브레멘 음악대**는 6대의 OV7670 카메라 영상을 다중 FPGA에서 실시간으로 분산 처리하고, 특정 색상 객체의 위치를 음계 신호로 변환하는 **인터랙티브 비전 오케스트라 시스템**입니다.

1대의 Master FPGA와 5대의 Slave FPGA를 병렬로 연결했으며, 5채널 SPI 통신으로 영상 데이터를 전송하고 I2C 통신으로 각 Slave의 음계 데이터를 수집합니다.

Master FPGA는 수집한 영상을 2×3 VGA 모자이크 화면으로 합성하고, 음계 데이터는 UART를 통해 PC로 전달하여 Python 기반 오디오 UI에서 악기 소리로 출력합니다.

---

## 📅 수행 기간

**2026.07.01 ~ 2026.07.21**

---

## 👥 프로젝트 형태

**6인 팀 프로젝트**

- FPGA Board: Digilent Basys 3 × 6대
- Camera Module: OV7670 × 6대
- Master FPGA: 1대
- Slave FPGA: 5대

---

## 🙋 담당 역할

본인은 전체 프로젝트에서 **Double Buffering(Ping-Pong) 기반 메모리 컨트롤러와 프레임 동기화 로직**을 담당했습니다.

- Master FPGA의 Ping-Pong 메모리 제어 구조 설계
- Memory A/B의 교대 Write·Read 제어
- SPI로 수신한 영상 데이터의 프레임 단위 저장
- VGA 출력과 카메라 프레임 사이의 동기화 처리
- 동일한 메모리에 대한 Read·Write 충돌 방지
- 영상 Tearing 및 프레임 데이터 덮어쓰기 방지
- Master–Slave Handshake 기반 Buffer 전환 제어
- 통합 시뮬레이션 및 FPGA 실기 동작 검증

> 팀원들과 Master·Slave FPGA를 통합했으며,  
> 본인은 Master FPGA의 영상 메모리 관리와 프레임 동기화를 중심으로 구현했습니다.

---

## 👨‍💻 Team & Roles

|    이름    | 악기 포지션 | 담당 역할 (Role)                                                       |
| :--------: | :---------: | :--------------------------------------------------------------------- |
| **이준형** |  🪘 Cymbals  | Master Integration, 전체 시스템 아키텍처 및 화면 병합 모듈 설계        |
| **곽은찬** |  🎻 Violin   | Python 실시간 영상/오디오 UI 구현 및 UART 통신 프로토콜 설계           |
| **안정현** | 🎷 Clarinet  | 다중 통신을 위한 I2C Master/Slave 프로토콜 및 FSM 설계                 |
| **윤지원** |   🥁 Drum    | YCoCg 2:1 영상 압축(Encoder) 및 복원(Decoder) 알고리즘 구현            |
| **최여지** |  🎺 Trumpet  | Double Buffering (Ping-Pong) 기반 메모리 컨트롤러 및 동기화 설계       |
| **최은수** |   🎹 Piano   | Slave Integration, OV7670 카메라 제어 및 영역 기반 객체 인식 모듈 구현 |

---

## 🛠 사용 기술

### HDL & Verification

- Verilog HDL
- SystemVerilog
- UVM

### FPGA & Video

- Digilent Basys 3
- Xilinx Artix-7
- OV7670 Camera
- VGA 640×480
- BRAM
- Double Buffering
- Clock Domain Synchronization

### Communication

- SPI 5-Channel
- I2C
- UART
- SCCB

### Software & Tools

- Xilinx Vivado 2020.2
- Python
- OpenCV
- Pygame
- Verdi

---

## ⚙️ 시스템 구성

![System Architecture](./readme_src/top_bd.png)

### Slave FPGA × 5

각 Slave FPGA는 OV7670 카메라 영상을 수집하고 다음 작업을 수행합니다.

1. OV7670 영상 데이터 수집
2. 영상 크기 Downscale
3. YCoCg 기반 영상 압축
4. 빨간색 객체 위치 검출
5. 검출 위치를 2-bit 음계 데이터로 변환
6. 영상 데이터는 SPI, 음계 데이터는 I2C로 Master에 전달

### Master FPGA × 1

Master FPGA는 5대의 Slave FPGA와 자체 카메라에서 데이터를 수집합니다.

1. 5채널 SPI 영상 데이터 수신
2. I2C를 통한 Slave 음계 데이터 수집
3. Ping-Pong Buffer 기반 프레임 저장 및 전환
4. YCoCg 영상 데이터 복원
5. 6개 영상을 2×3 VGA 모자이크 화면으로 합성
6. 12-bit 음계 데이터를 UART Packet으로 변환
7. PC의 Python 오디오 UI로 데이터 전송

### PC Application

PC에서는 UART로 수신한 음계 데이터를 기반으로 각 카메라에 대응하는 악기 소리를 재생합니다.

```text
OV7670 Camera × 6
        ↓
Slave FPGA × 5 ── SPI Video ──────┐
        │                          │
        └──── I2C Scale Data ──────┤
                                   ↓
                             Master FPGA
                                   ↓
                       Ping-Pong Frame Buffer
                                   ↓
                         2×3 VGA Mosaic Output
                                   ↓
                            UART 3-Byte Packet
                                   ↓
                      Python Audio / Visual UI
```

---

## ✨ 주요 구현 내용

### 1. Ping-Pong Double Buffering

한정된 BRAM에서 영상 입력과 출력을 동시에 처리하기 위해 Memory A와 Memory B를 번갈아 사용하는 Ping-Pong Buffer 구조를 적용했습니다.

```text
Camera/SPI Write → Memory A
VGA Read         → Memory B
