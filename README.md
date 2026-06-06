# SPI

## Overview

SystemVerilog로 구현한 SPI Master/Slave 설계임. SPI Master는 Mode 0부터 Mode 3까지 지원함. SPI 클럭 속도를 설정할 수 있으며, 2개의 Chip Select를 통해 통신할 Slave를 선택함.

기본 SPI RTL, Master/Slave UVM testbench, AXI4-Lite 기반 SPI Master 및 bare-metal C application으로 구성함.

## Specifications

- 8비트 Full-Duplex SPI 통신
- MSB First 전송
- SPI Mode 0, 1, 2, 3 Master
- SPI Mode 0 Slave
- SPI 클럭 속도 조절 기능
- 2개의 Active-Low Chip Select
- Master 및 Slave UVM 검증
- AXI4-Lite 기반 SPI Master
- HAL, Driver, Application 계층의 C 코드
- SPI Slave 7-Segment Display 출력 모듈

## SPI Master Architecture

`SPI/rtl/spi_master.sv`는 `IDLE`, `START`, `DATA`, `STOP` 상태로 구성한 SPI Master임.

`start` 입력 시 `tx_data`를 shift register에 저장하고 `slave_sel`에 해당하는 `cs_n`을 Low로 설정함. SCLK의 첫 번째 edge와 두 번째 edge에서 CPHA 값에 따라 MOSI 출력과 MISO sampling을 수행함.

| 신호 | 방향 | 설명 |
| --- | --- | --- |
| `start` | Input | 1 byte transaction 시작 |
| `tx_data[7:0]` | Input | 송신 데이터 |
| `clk_div[7:0]` | Input | SPI 클럭 속도 설정값 |
| `slave_sel` | Input | Slave 0 또는 Slave 1 선택 |
| `cpol` | Input | SCLK idle level |
| `cpha` | Input | Data sampling phase |
| `rx_data[7:0]` | Output | 수신 데이터 |
| `busy` | Output | Transaction 진행 상태 |
| `done` | Output | Transaction 완료 pulse |
| `sclk` | Output | SPI serial clock |
| `mosi` | Output | Master Out, Slave In |
| `miso` | Input | Master In, Slave Out |
| `cs_n[1:0]` | Output | Active-Low Chip Select |

SCLK 주파수는 system clock과 `clk_div` 값으로 결정함.

```text
f_sclk = f_clk / (2 x (clk_div + 1))
```

### SPI Mode

| Mode | CPOL | CPHA | SCLK Idle | Sampling |
| --- | --- | --- | --- | --- |
| 0 | 0 | 0 | Low | First edge |
| 1 | 0 | 1 | Low | Second edge |
| 2 | 1 | 0 | High | First edge |
| 3 | 1 | 1 | High | Second edge |

## SPI Slave Architecture

`SPI/rtl/spi_slave.sv`는 SPI Mode 0으로 동작함. SCLK rising edge에서 MOSI를 sampling하고 SCLK falling edge에서 다음 MISO bit를 출력함.

| 신호 | 방향 | 설명 |
| --- | --- | --- |
| `tx_data[7:0]` | Input | Master에 전송할 데이터 |
| `rx_data[7:0]` | Output | Master로부터 수신한 데이터 |
| `valid` | Output | 8비트 수신 완료 pulse |
| `sclk` | Input | SPI serial clock |
| `mosi` | Input | Master 송신 데이터 |
| `miso` | Output | Slave 송신 데이터 |
| `cs_n` | Input | Active-Low Chip Select |

SCLK, CS 및 MOSI 입력은 2-FF synchronizer를 통해 system clock domain으로 동기화함. CS가 High인 동안 `tx_data`를 shift register에 저장하고, CS가 Low가 되면 8비트 송수신을 수행함.

## AXI4-Lite Interface

`AXI4_SPI`는 SPI Master core와 32비트 AXI4-Lite Slave register interface를 결합한 설계임. AXI4-Lite SPI Master는 Mode 0으로 동작함.

| Offset | Register | 비트 구성 |
| --- | --- | --- |
| `0x00` | Control | `[0]=START`, `[1]=Slave Select` |
| `0x04` | TX Data | `[7:0]=tx_data` |
| `0x08` | Status/RX | `[0]=busy`, `[1]=done`, `[15:8]=rx_data` |
| `0x0C` | SPI Clock 설정 | `[7:0]=clk_div` |

`AXI4_SPI/src`의 C 코드는 HAL, Driver, Application 계층으로 구성함. UART 입력 `1`, `2`로 Slave를 선택하고 입력 문자를 SPI로 전송하며, `0` 입력 시 두 Slave의 7-Segment Display 데이터를 초기화함.

## Verification

SPI Master, SPI Slave 및 AXI4-Lite SPI Master를 각각 독립된 UVM testbench에서 검증함. Monitor에서 SPI 신호와 수신 데이터를 수집하고, Scoreboard에서 예상 데이터와 DUT 출력값을 비교함.

### SPI Master Test

MISO를 MOSI에 연결한 Loopback 구조에서 SPI Mode, SPI 클럭 속도 및 송수신 데이터 일치 여부를 검증함.

| Test | Transaction | 검증 내용 |
| --- | --- | --- |
| Random Smoke Test | 300 | 랜덤 `tx_data`, SPI Mode 0~3 및 SPI 클럭 조합 |
| Pattern Test | 300 | `0xAA`, `0x55` 반복 패턴과 랜덤 SPI Mode 및 SPI 클럭 조합 |

Scoreboard에서 `tx_data`, MOSI 수집 데이터 및 `rx_data`를 비교함.

### SPI Slave Test

Driver에서 SPI Mode 0 Master 신호를 생성하여 Slave의 MOSI 수신, MISO 송신 및 `valid` 출력을 검증함.

| Test | Transaction | 검증 내용 |
| --- | --- | --- |
| Random Smoke Test | 100 | 랜덤 `tx_data`와 SCLK Half-Period 조합 |
| Pattern Test | 100 | `0xAA`, `0x55` 반복 패턴과 랜덤 SCLK Half-Period 조합 |

Scoreboard에서 Slave 송신 데이터, MISO 수집 데이터 및 MOSI 수신 데이터를 비교함.

### AXI4-Lite SPI Master Test

SPI Mode 0과 `CLKDIV=4` 조건에서 AXI4-Lite 레지스터 접근과 SPI 전송 동작을 통합 검증함.

| Test | Transaction | 검증 내용 |
| --- | --- | --- |
| Random AXI/SPI Test | 1,000 | Slave 0/1, TX Data 및 MISO 응답 데이터 랜덤 검증 |

Control, TX Data, Status/RX 및 SPI Clock 레지스터의 Write/Read 동작을 확인함. 선택된 Chip Select, MOSI 전송 데이터, `STATUS[15:8]` RX Data 및 `STATUS[0]`의 `busy` 상태를 예상값과 비교함.

### Functional Coverage

| 검증 대상 | Coverpoint | 검증 범위 |
| --- | --- | --- |
| SPI Master | SPI Mode | Mode 0, 1, 2, 3 |
| SPI Master | SPI Clock | `clk_div` 설정값 |
| SPI Master | Data Pattern | `00`, `FF`, `AA`, `55`, Low, Mid, High |
| SPI Master | Cross Coverage | SPI Mode x SPI Clock, SPI Mode x Data Pattern |
| SPI Slave | Data Pattern | `00`, `FF`, `AA`, `55`, Low, Mid, High |
| SPI Slave | SCLK Half-Period | `3`, `4`, `5`, `8`, `10` cycle |
| SPI Slave | Cross Coverage | Data Pattern x SCLK Half-Period |
| AXI4-Lite SPI Master | Slave Select | Slave 0, Slave 1 |
| AXI4-Lite SPI Master | TX/RX Data | `00`, `FF`, Low, Mid, High |
| AXI4-Lite SPI Master | Cross Coverage | Slave Select x TX Data, Slave Select x RX Data |

## Verification Results

Scoreboard에서 예상값과 실제 송수신 데이터를 비교한 결과, 모든 테스트가 mismatch 없이 Pass함.

| 검증 대상 | Test | 결과 | Coverage |
| --- | --- | --- | --- |
| SPI Master | Random Smoke Test | Pass | ≈ 77% |
| SPI Master | Pattern Test | Pass | ≈ 88% |
| SPI Slave | Random Smoke Test | Pass | ≈ 81% |
| SPI Slave | Pattern Test | Pass | ≈ 89% |
| AXI4-Lite SPI Master | Random AXI/SPI Test | Pass | 100% |

Master와 Slave 모두 Pattern Test에서 Random Smoke Test보다 높은 Coverage를 달성함. AXI4-Lite SPI Master는 100% Coverage를 달성함.

## FPGA Board Test

RTL simulation과 UVM 검증 이후 FPGA 보드에서 기본 SPI Master/Slave와 AXI4-Lite SPI Master의 실제 입출력 동작을 확인함.

### SPI Master/Slave Demo

`SPI/demo_spi/demo_spi_master.sv`와 `SPI/demo_spi/demo_spi_slave.sv`를 이용하여 스위치와 LED 기반의 SPI 통신을 검증함.

`demo_spi_master`는 Master 측의 8비트 switch 값을 `tx_data`로 전송하고, 선택한 Slave에서 반환한 `rx_data`를 8비트 LED에 출력함. SPI Mode 0으로 동작하며 `slave_sel` 입력으로 `CS0` 또는 `CS1`을 선택함.

`demo_spi_slave`는 두 개의 SPI Slave를 구성함. 각 Slave는 수신한 MOSI 데이터를 LED에 출력하고, 해당 Slave의 switch 값을 MISO를 통해 Master로 반환함.

```text
Master Switch
     |
     v
 SPI Master -- MOSI --> Selected SPI Slave --> Slave LED
 SPI Master <-- MISO -- Selected SPI Slave <-- Slave Switch
     |
     v
Master LED
```

| 테스트 항목 | 확인 내용 | 결과 |
| --- | --- | --- |
| Master Write | Master switch 값이 선택된 Slave의 LED에 출력됨 | Pass |
| Master Read | 선택된 Slave의 switch 값이 Master LED에 출력됨 | Pass |
| Slave Select | `slave_sel`에 따라 CS0/CS1 대상이 변경됨 | Pass |
| Full-Duplex | MOSI 전송과 MISO 수신이 동일 transaction에서 수행됨 | Pass |

스위치 값을 변경한 후 SPI transaction을 실행하여 Master와 Slave의 LED 출력이 전달 데이터와 일치하는 것을 확인함.

### AXI4-Lite SPI Master Demo

`AXI4_SPI`의 SPI Master와 `SPI/demo_spi/demo_slave_fnd.sv`를 연결하여 AXI4-Lite register 제어 및 실제 SPI 통신을 검증함.

`demo_spi_slave_fnd`는 CS0과 CS1에 대응하는 두 개의 SPI Slave를 구성함. 각 Slave는 Master로부터 수신한 8비트 데이터를 7-Segment Display에 표시하고, Slave 측 switch 값을 MISO 응답 데이터로 반환함.

UART terminal에서 명령과 송신 문자를 입력하고, Vitis application에서 AXI4-Lite SPI register를 제어함.

| 테스트 항목 | 확인 내용 | 결과 |
| --- | --- | --- |
| UART Terminal | 명령어 입력, Slave 선택 메시지 및 TX/RX 응답 출력 | Pass |
| CS0/CS1 선택 | Control register의 Slave Select bit로 대상 Slave 선택 | Pass |
| SPI Write | UART로 입력한 문자가 선택된 Slave의 FND에 정상 표시됨 | Pass |
| SPI Read | 선택된 Slave의 switch 조작값이 Master RX data로 정상 수신됨 | Pass |
| Clear | UART에서 `0` 입력 시 두 Slave FND가 `0000`으로 초기화됨 | Pass |

UART terminal에서 `1` 또는 `2`를 입력하여 Slave 0과 Slave 1을 선택함. 이후 입력한 문자는 TX Data register를 통해 선택된 Slave로 전송되며, 해당 데이터가 대상 FND에 표시되는 것을 확인함.

동일한 SPI transaction에서 선택된 Slave의 switch 값이 MISO로 반환되고, AXI Status/RX register를 통해 Master에 정상 수신되는 것을 UART 응답으로 확인함.

## Directory Structure

```text
SPI/
├── SPI/
│   ├── rtl/
│   │   ├── spi_master.sv
│   │   └── spi_slave.sv
│   ├── tb/
│   │   ├── TB_UVM_SPI_MASTER.sv
│   │   └── TB_UVM_SPI_SLAVE.sv
│   └── demo_spi/
│       ├── demo_spi_master.sv
│       ├── demo_spi_slave.sv
│       └── demo_slave_fnd.sv
└── AXI4_SPI/
    ├── hdl/
    │   ├── spi_master.sv
    │   └── spi_master_slave_lite_v1_0_S00_AXI.v
    ├── tb/
    │   └── tb_spi_master.sv
    └── src/
        ├── main.c
        ├── APP/
        ├── DRIVER/
        └── HAL/
```
