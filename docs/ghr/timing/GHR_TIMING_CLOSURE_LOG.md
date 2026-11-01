# GHR registered-I/O timing-closure log

This document records the engineering decisions, functional issues, verification work, synthesis results, PrimeTime results, and remaining timing work for the registered-input/registered-output Global History Register. It is a record of the implemented work rather than an instruction to redesign the block.

## 1. Motivation and architectural change

The earlier GHR timing study inserted an internal register at either target_index or read_bank/read_row. Those boundary experiments removed the original pure input-to-output combinational path, but they distributed timing margin unevenly and changed the latency inside the read-address path.

A separate registered-I/O version was therefore developed. Functional inputs are captured at the block boundary, the internal GHR operation is performed from registered state, and incoming_packet_o, expiring_packet_o, and output_valid_o are captured before leaving the block. This gives the block explicit timing boundaries, simplifies integration timing budgets, and provides natural locations for future isolation or retention logic.

The principal registers are:

| Label | RTL state |
|---|---|
| R1 | br_valid_i_reg |
| R2 | br_packet_i_reg[6:0] |
| R3 | misprediction_i_reg |
| R4 | mispredicted_table_depth_i_reg[5:0] |
| R5 | recovery_active_i_reg |
| R6 | input_stage_valid_reg |
| R7 | head_ptr[5:0] |
| R8 | output_valid_o_reg |
| R9 | incoming_packet_o_reg[6:0] |
| R10 | expiring_packet_o_reg[0:6][6:0] |

![Registered-I/O GHR architecture](../../images/ghr/registered_io/ghr_registered_io_architecture.png)

## 2. Functional and verification issues encountered

### 2.1 Enable bubbles and pointer progression

Alternating enable sequences exposed a control-alignment problem. When en_i was low between accepted transactions, combinational next_head_ptr logic could fall back to the current head_ptr while a previously accepted operation was still moving through the registered pipeline. The next active edge could therefore retain an old pointer value and later writes appeared to skip or overwrite history positions.

The correction was to treat pointer movement as part of the accepted transaction. The pointer update, write address, write enable, and registered packet data must all describe the same operation. Alternating-enable and two-enabled/one-disabled sequences were used specifically to expose this condition.

### 2.2 Memory write control and registered packet data

A second failure occurred when the bank-memory write condition used raw branch-valid control while the memory data came from br_packet_i_reg. That combined control from one transaction with data from another transaction. It was especially visible in back-to-back rollback and replacement traffic.

The memory write qualification was aligned with the registered branch transaction. Address, enable, and packet data are now evaluated from one pipeline stage. This eliminated missing writes and the delayed accumulation of packet values in later cycles.

### 2.3 Incoming and expiring packet alignment

The downstream folding logic consumes incoming_packet_o and the seven expiring packets as one logical update. The testbench therefore checks them together with output_valid_o. During development, the expiring path initially appeared later because it includes target-index calculation, bank/row translation, memory selection, and output registration. The control/data pipeline was adjusted so that the incoming packet, expiring packet bundle, and valid indication refer to the same accepted branch.

### 2.4 Scoreboard pointer reference

The original reference calculation used next_head_ptr when determining the expected expiring packet. That produced an off-by-one history interpretation. If the current free head is pointer 3, depth 2 corresponds to pointer 1 under a conventional distance calculation; the scoreboard must use the same architectural reference point and pipeline cycle as the RTL. The reference model was updated to model accepted operations and delayed outputs explicitly instead of comparing every output to same-cycle raw inputs.

### 2.5 Reset and startup X values

The first monitor samples occurred before reset had initialized the asynchronous registers, producing X mismatches at time zero. Reset-directed testing now asserts active-low reset, checks asynchronous clearing, holds reset across clock edges, deasserts it between edges, and verifies that operation restarts from pointer zero.

### 2.6 Bank clock behavior

The per-bank gated clocks are expected to be zero whenever that bank is not selected for a valid write. Seeing all gated_bank_clk values low in the middle of stimulus is not automatically a failure; it is correct when no bank write is accepted. The important check is that exactly the selected bank receives a write edge and that its address, data, and enable belong to the same registered transaction.

### 2.7 Illegal rollback-depth stimulus

The final multi-sequence regression reported illegal registered misprediction depth zero during rollback-focused sequences. Depth zero is outside the legal rollback protocol used by the design. The errors were traced to stimulus/scoreboard protocol handling rather than the legal GHR datapath. This case is parked as an illegal-input test: legal functional timing work proceeds with rollback depth in the range 1 through 35, while a later negative test can define the desired response to depth zero explicitly.

## 3. Timing-path improvement

### 3.1 Original registered-I/O limiting arithmetic

The first registered-I/O implementation calculated rollback_ptr and then calculated rollback_incremented_ptr in a second dependent step. In the rollback-plus-valid-branch mode, this created serial arithmetic before the target-index, address-decode, and memory-selection logic.

At 600 MHz, the pre-optimization head-pointer-to-expiring path had:

| Measurement | Value |
|---|---:|
| Data arrival | 1605.8624 ps |
| Setup slack | +48.2930 ps |

### 3.2 Direct rollback-plus-increment calculation

The rollback-plus-increment result was reformulated as a direct extended-width operation equivalent to:

head_ptr + 1 - mispredicted_table_depth, modulo 36.

rollback_ptr remains available for rollback-only behavior and write-address selection. The direct expression removes the dependency in which an incrementer waits for rollback subtraction to finish.

After synthesis and PrimeTime analysis at 600 MHz:

| Measurement | Before | After | Improvement |
|---|---:|---:|---:|
| Head-pointer-to-expiring arrival | 1605.8624 ps | 1377.3075 ps | 228.5549 ps |
| Setup slack | +48.2930 ps | +276.8159 ps | +228.5229 ps |
| Path-delay reduction | — | — | approximately 14.25% |

The overall worst 600 MHz path then moved to raw en_i control feeding an expiring output register. That path arrived at 1439.5693 ps and retained +214.5541 ps of setup slack. Its large control nets had fanouts of 57 and 64.

## 4. 600 MHz implementation summary

| Metric | Registered-I/O GHR |
|---|---:|
| Clock period | 1666.67 ps |
| Worst setup slack after arithmetic optimization | +214.5541 ps overall |
| Worst hold slack | +11.9252 ps |
| Sequential cells | 332 |
| Total cell area | 5015.2867 |
| Estimated synthesis power | 0.261 mW |
| Direct functional input-to-output paths | 0 |
| Setup violations | 0 |
| Hold violations | 0 |

## 5. 700 MHz timing closure

The same RTL was synthesized again using a 1428.571 ps clock period. PrimeTime reproduced the Design Compiler result closely.

| Metric | 700 MHz result |
|---|---:|
| Clock period | 1428.571 ps |
| Worst setup startpoint | head_ptr_reg_1_ |
| Worst setup endpoint | expiring_packet_o_reg_reg_2__6_ |
| Data arrival | 1374.0164 ps |
| Data required | 1416.0233 ps |
| Worst setup slack | +42.0069 ps |
| Worst hold slack | +11.9252 ps |
| Worst input-to-register slack | +119.3126 ps |
| Worst register-to-output slack | +736.2537 ps |
| Total cell area | 5014.5869 |
| Estimated synthesis power | 0.303 mW |
| Direct functional input-to-output paths | 0 |
| Setup/hold violations | 0 / 0 |

The timing-equivalent minimum period estimated from this mapping is approximately 1386.563 ps, corresponding to about 721.2 MHz. A 720 MHz run would therefore have only about 2.3 ps of nominal margin if the mapping remained unchanged. This estimate is useful for characterization, but it is not a robust signoff target because clock uncertainty, extracted interconnect, variation, and physical implementation margin are not yet included.

### 5.1 Whole-design PrimeTime checkpoint after the first manual ECO set

The accepted mapped-cell changes were saved from Design Vision as a separate 700 MHz manual-ECO netlist and SDC, then analyzed in PrimeTime without overwriting the original 700 MHz synthesis output. This checkpoint preceded the later U4286 and U4276 experiments documented in Section 6.4.9.

| Measurement | Original 700 MHz mapping | Manual-ECO checkpoint | Change |
|---|---:|---:|---:|
| Global worst setup slack | +42.0069 ps | +108.6811 ps | +66.6742 ps |
| Global worst data arrival | 1374.0164 ps | 1307.3422 ps | -66.6742 ps |
| Worst hold slack | +11.9252 ps | +11.9252 ps | unchanged |
| Setup violations | 0 | 0 | unchanged |
| Hold violations | 0 | 0 | unchanged |
| Direct functional input-to-output paths | 0 | 0 | unchanged |

The corresponding timing-equivalent period was approximately 1319.8888 ps, or 757.6 MHz. This is a characterization estimate under the current pre-layout assumptions, not a signoff frequency. The analysis still uses ideal clocks, no clock uncertainty, no extracted interconnect parasitics, and one TT operating condition.

The manual-ECO PrimeTime cell-size report confirmed the intended U3908-path changes. It also reported U4278=NAND2x1p5, while the exploratory Design Vision record and the reproducible ECO script identify the accepted U4278 target as NAND2x1. This discrepancy is explicitly left open: the final reproducible DC run must compare the generated netlist against the ECO script, select one intended U4278 size based on a controlled timing/area measurement, and regenerate the PrimeTime checkpoint. The 757.6 MHz estimate therefore describes the saved manual-ECO netlist exactly; it must not be attributed blindly to a different reconstructed cell-size list.

## 6. Current limiting path

The current path is:

head_ptr_reg[1] -> pointer/next-head arithmetic -> target_index[2] for depth 6 -> read-bank/read-row decode -> 9-bank by 4-row history selection -> expiring_packet_o_reg[2][6].

The path contains two synthesized arithmetic groups, address decoding, high-fanout intermediate nets, and the memory-read selection tree. The largest observed local increments include:

| Cell/net | Observation |
|---|---|
| U4278 driving n3542 | 113.1472 ps, fanout 30 |
| U3734 driving n4302 | 85.4915 ps, fanout 17 |
| U2378 | 71.5585 ps |
| U2467 | 67.9924 ps |
| DP_OP_863...U18/SN | 58.5042 ps |
| U2370 | 58.9674 ps |

The DP_OP cells are Design Compiler datapath operators. FAx1 cells expose A, B, and CI inputs and inverted carry/sum outputs CON and SN. Consecutive CON-to-CI connections identify carry propagation; an SN endpoint represents the inverted sum result used by downstream logic.

![Critical path part 1](../../images/ghr/registered_io/ghr_2reg_700mhz_critical_path_part1.png)
![Critical path part 2](../../images/ghr/registered_io/ghr_2reg_700mhz_critical_path_part2.png)
![Critical path part 3](../../images/ghr/registered_io/ghr_2reg_700mhz_critical_path_part3.png)
![Critical path part 4](../../images/ghr/registered_io/ghr_2reg_700mhz_critical_path_part4.png)
![Critical path part 5](../../images/ghr/registered_io/ghr_2reg_700mhz_critical_path_part5.png)

The next optimization step is deliberately not chosen from gate delay alone. The synthesized target_index[2] boundary is being located in Design Vision so the delay can be separated into pointer arithmetic, target-index arithmetic, bank/row decoding, and memory selection before another RTL change is made.

### 6.1 Confirmed critical-path partition

Design Vision connectivity tracing separated the 700 MHz path into the following functional sections. The combinational delay excludes the 77.4716 ps clock-to-Q delay of head_ptr_reg[1].

| Section | Function | Measured delay | Share of combinational delay |
|---|---|---:|---:|
| A | Pointer calculation and next-head-pointer selection | 458.7063 ps | 35.4% |
| B | target_index[2] arithmetic for history depth 6 | 336.2113 ps | 25.9% |
| C | Bank/row decoding and select distribution | 264.4337 ps | 20.4% |
| D | Bank-memory data mux and output logic | 237.1933 ps | 18.3% |

Sections A and B together consume 794.9176 ps, or approximately 61.3% of the combinational path. The A/B boundary is the high-fanout n4302 node driven by U3734/Y. The B/C boundary is n3338, the U4268/SN full-adder output that divides into the bank and row decoding cones. The C/D boundary is n3542, the final decoded selection term driven by U4278/Y.

Section C is:

```text
n3338 -> U2416 -> U2860 -> U4270 -> U2378 -> U4278 -> n3542
```

U4278 is a NAND2xp5 cell driving 30 loads. It contributes 113.1473 ps and produces a 199.6314 ps output transition. Its load set consists primarily of OAI22/AOI22 memory-selection gates, confirming that n3542 is a shared bank/row selection signal rather than stored packet data.

Section D is:

```text
n3542
  -> U2611/B2  (AOI22xp33, 41.6407 ps)
  -> U4292/A2  (OAI31xp33, 28.1354 ps)
  -> U4293/C   (A2O1A1Ixp33, 29.7069 ps)
  -> U2370/B   (NAND2xp33, 58.9673 ps)
  -> U2534/B2  (OAI22xp33, 27.4343 ps)
  -> U4307/A3  (OAI32xp33, 26.1658 ps)
  -> U4308/C   (A2O1A1Ixp33, 25.1429 ps)
  -> expiring_packet_o_reg[2][6]/D
```

U2611 implements the first memory-data selection term. Its critical inputs are C1_DATA1_1 on B1 and the decoded n3542 select on B2; n3348 and n3544 form the competing AOI22 term.

### 6.2 Drive-strength timing note

Cell drive strength describes the current capability of a standard cell's output stage. In this ASAP7 NAND2 family, the approximate strength order is xp33, xp5, xp67, x1, x1p5, and x2. A stronger cell has lower effective output resistance and therefore charges or discharges a capacitive load faster. A first-order interpretation is cell delay proportional to output resistance multiplied by load capacitance.

Upsizing a cell can reduce its output transition and downstream arrival time, but it also increases the cell's input capacitance. The preceding gate must then drive a larger load. Stronger cells also generally increase area, leakage, and internal switching capacitance, and a faster minimum-delay path can reduce hold margin. Consequently, the full timing path, area, power, and hold result must be compared rather than judging only the resized cell's local delay.

For U4278, upsizing should improve its ability to drive the 30 memory-mux loads, while increasing the load presented to U2378. A temporary Design Vision change from NAND2xp5 to NAND2x1 is therefore used only as a controlled in-memory experiment. The saved DDC and RTL remain unchanged until the total-path benefit and tradeoffs are measured.
### 6.3 Temporary U4278 drive-strength experiment

U4278 was initially resized as an in-memory Design Vision experiment from NAND2xp5 to NAND2x1. After the result was accepted, the change was added to the post-compile sizing ECO described in Section 6.5. After `update_timing`, the worst path to expiring_packet_o_reg[2][6] improved as follows:

| Measurement | Original mapping | U4278 resized |
|---|---:|---:|
| Data arrival | 1374.0162 ps | 1354.6036 ps |
| Setup slack | +42.0071 ps | +61.4197 ps |
| End-to-end improvement | — | 19.4126 ps |

The reported critical path no longer passed through U4278/n3542. It migrated to the parallel n3544 selection branch through U2859, U2846, U3732, and U4277. U4277 is also a NAND2xp5 cell driving 30 loads; it contributed 110.1544 ps and produced a 199.0981 ps transition. The path then entered U2611 through A2 instead of through the original n3542/B2 term.

This migration demonstrates that the memory read is implemented by multiple nearly balanced high-fanout decode branches. Strengthening only U4278 improves timing, but another equivalent branch becomes limiting. A durable implementation should therefore consider the complete family of high-fanout bank/row decode signals, synthesis transition/fanout constraints, or a buffered decode structure rather than treating U4278 as an isolated RTL problem.

### 6.4 Manual sizing of the U3908 path

The next detailed study locked the following route so that Design Compiler did not substitute a different internal branch having the same register endpoints:

```text
head_ptr_reg_1_/QN
  -> U3734/Y, n4302 fanout 17
  -> U3733/Y, n3063 fanout 10
  -> U3908/Y, n3089 fanout 30
  -> U2373/Y, n3095 fanout 7
  -> expiring_packet_o_reg_reg_0__0_/D
```

Using only `-from` and `-to` was insufficient for controlled comparison because several combinational routes connect the same registers. After one route became faster, `report_timing` selected a parallel route containing fanout-29 and fanout-28 nets. The controlled reports therefore used explicit `-through` points for U3734, U3908, and later U2373.

The accepted cell-size changes are:

| Cell | Original | Accepted | Reason |
|---|---|---|---|
| U3908 | NAND2x1 | NAND2x1p5 | Improved drive of the fanout-30 n3089 net |
| U3733 | NOR2xp33 | NOR2xp67 | Recovered the U3908 input-capacitance penalty and improved n3063 slew |
| U3734 | OAI21xp5 | OAI21x1 | Improved the fanout-17 n4302 transition |
| U3726 | NOR2xp33 | NOR2xp67 | Improved a 6.0915-capacitance, fanout-4 net and the downstream inverter |
| U2467 | NOR2xp33 | NOR2xp67 | Reduced its own delay and improved U3589 input slew |
| U3589 | NAND2xp33 | NAND2xp5 | Improved U3726 input slew with no measured cell-area increase |
| U2373 | NAND2xp33 | NAND2xp5 | Improved the fanout-7 n3095 transition with no measured cell-area increase |

Key controlled experiments were:

| Experiment | Path arrival | Slack | Timing gain | Total cell area | Area change |
|---|---:|---:|---:|---:|---:|
| After U3734/U3733/U3908 sizing | 1238.9390 ps | 177.0844 ps | reference | 5018.552648 | reference |
| Add U3726xp67 | 1204.6016 ps | 211.4218 ps | 34.3374 ps | 5018.552648 | 0 |
| U2467xp67 only, after U3726 | 1190.9958 ps | 225.0275 ps | 13.6058 ps | 5019.019208 | +0.466560 |
| U3589xp5 only, after U3726 | 1195.8313 ps | 220.1920 ps | 8.7703 ps | 5018.552648 | 0 |
| U2467xp67 and U3589xp5 | 1182.4242 ps | 233.5991 ps | 22.1774 ps | 5019.019208 | +0.466560 |
| Add U2373xp5 | 1160.2734 ps | 255.7499 ps | 22.1508 ps | 5019.019208 | 0 |

The combined U2467/U3589 improvement was nearly additive: the separate gains summed to 22.3761 ps and the combined measured gain was 22.1774 ps. U2373xp5 reduced its own delay from 49.0334 ps to 30.5790 ps and improved its output transition from 87.1396 ps to 46.0851 ps. Its predecessor U2389 incurred only a 1.9591 ps delay penalty.

These changes are post-compile mapped-cell ECOs rather than RTL architectural modifications. They are reproduced by `scripts/ghr/ghr_2reg_700mhz_manual_sizing_eco.tcl`, sourced immediately after `compile_ultra`. The ECO script fails if a required mapped instance or library cell is missing, because generated U-number instance names can change when RTL, constraints, libraries, or the synthesis version change. Accepted cells are marked `dont_touch` after sizing so a later incremental optimization does not silently resize them.

#### 6.4.1 Measurement method

Each sizing decision used the same sequence:

1. Keep the startpoint, endpoint, and required `-through` cells fixed.
2. Record the predecessor-cell delay and transition before resizing.
3. Resize exactly one cell unless the experiment explicitly tests a combination.
4. Run `update_timing` without recompiling the netlist.
5. Record the resized-cell delay, output transition, downstream-cell effects, endpoint arrival, and slack.
6. Run `report_area` and compare total cell area.
7. Keep the change only when the complete-path benefit outweighed its predecessor penalty and area cost.

This distinction is important because a stronger cell has greater input capacitance. A local cell-delay reduction is not sufficient evidence: its predecessor can become slower, and another parallel route can become the new limiting route.

#### 6.4.2 U3908: drive the fanout-30 n3089 net

U3908 was changed from NAND2x1 to NAND2x1p5. The stronger input capacitance increased the n3063 load seen by U3733, but it substantially improved the transition delivered to the 30 loads on n3089.

| Measurement | U3908x1 | U3908x1p5 | Change |
|---|---:|---:|---:|
| n3063 capacitance | 4.7320 | 5.2393 | +0.5073 |
| U3733 delay | 55.8629 ps | 60.8232 ps | +4.9603 ps |
| U3733 output transition | 100.7210 ps | 110.4547 ps | +9.7337 ps |
| U3908 delay | 87.4867 ps | 68.5869 ps | -18.8998 ps |
| U3908 output transition | 133.2326 ps | 93.4924 ps | -39.7402 ps |
| U2553 delay | 28.8574 ps | 25.2426 ps | -3.6148 ps |
| Endpoint arrival | 1342.0205 ps | 1322.9061 ps | -19.1144 ps |
| Path slack | 74.0028 ps | 93.1172 ps | +19.1144 ps |

Decision: accept U3908x1p5. The 4.9603 ps predecessor penalty was outweighed by the U3908 and downstream improvements.

#### 6.4.3 U3733: recover the U3908 input-load penalty

U3733 was changed from NOR2xp33 to NOR2xp67. The larger U3733 input increased the load on U2801, but it improved both its own fanout-10 output and the input slew seen by U3908.

| Measurement | U3733xp33 | U3733xp67 | Change |
|---|---:|---:|---:|
| U3733 input-net capacitance | 0.3428 | 0.6903 | +0.3475 |
| U2801 delay | 19.0338 ps | 23.5619 ps | +4.5281 ps |
| U3733 delay | 60.8232 ps | 37.4639 ps | -23.3593 ps |
| U3733 output transition | 110.4547 ps | 62.6926 ps | -47.7621 ps |
| U3908 delay | 68.5869 ps | 54.4194 ps | -14.1675 ps |
| Endpoint arrival | 1322.9061 ps | 1289.9075 ps | -32.9986 ps |
| Path slack | 93.1172 ps | 126.1158 ps | +32.9986 ps |

Decision: accept U3733xp67. It compensated for the U3908 input capacitance and generated an additional downstream gain.

#### 6.4.4 U3734: drive the fanout-17 n4302 net

U3734 was changed from OAI21xp5 to OAI21x1. Its input capacitance approximately doubled, slightly slowing U3812, but its fanout-17 output transition improved by more than 75 ps.

| Measurement | U3734xp5 | U3734x1 | Change |
|---|---:|---:|---:|
| n2721 capacitance | 0.5686 | 1.1405 | +0.5719 |
| U3812 delay | 24.3759 ps | 26.8708 ps | +2.4949 ps |
| U3812 output transition | 23.6769 ps | 29.8951 ps | +6.2182 ps |
| U3734 delay | 85.4915 ps | 52.2063 ps | -33.2852 ps |
| U3734 output transition | 164.8443 ps | 89.5925 ps | -75.2518 ps |
| Endpoint arrival | 1289.9075 ps | 1238.9390 ps | -50.9685 ps |
| Path slack | 126.1158 ps | 177.0844 ps | +50.9686 ps |

Decision: accept U3734x1. The predecessor penalty was small compared with the direct and propagated improvements.

#### 6.4.5 U3726: improve the n4566 drive and downstream inverter

U3726 was changed from NOR2xp33 to NOR2xp67. The n2722 load on U3589 increased, but U3726 and its downstream inverter both became faster.

| Measurement | U3726xp33 | U3726xp67 | Change |
|---|---:|---:|---:|
| n2722 capacitance | 0.3428 | 0.6903 | +0.3475 |
| U3589 delay | 22.6797 ps | 28.8242 ps | +6.1445 ps |
| U3589 output transition | 47.9270 ps | 60.0266 ps | +12.0996 ps |
| U3726 delay | 77.5692 ps | 51.2617 ps | -26.3075 ps |
| U3726 output transition | 134.8564 ps | 81.7476 ps | -53.1088 ps |
| U3817 delay | 48.8340 ps | 38.5978 ps | -10.2362 ps |
| Endpoint arrival | 1238.9390 ps | 1204.6016 ps | -34.3374 ps |
| Path slack | 177.0844 ps | 211.4218 ps | +34.3374 ps |

Decision: accept U3726xp67. The complete path improved by 34.3374 ps despite the U3589 penalty.

#### 6.4.6 Controlled U2467 and U3589 sizing matrix

U2467 and U3589 were tested separately and together. This avoided attributing a combined result to the wrong cell.

| Configuration | Endpoint arrival | Timing gain from 1204.6016 ps | Total cell area | Area change |
|---|---:|---:|---:|---:|
| Both original: U2467xp33, U3589xp33 | 1204.6016 ps | reference | 5018.552648 | reference |
| U2467xp67 only | 1190.9958 ps | 13.6058 ps | 5019.019208 | +0.466560 |
| U3589xp5 only | 1195.8313 ps | 8.7703 ps | 5018.552648 | 0 |
| U2467xp67 and U3589xp5 | 1182.4242 ps | 22.1774 ps | 5019.019208 | +0.466560 |

The separate improvements summed to 22.3761 ps; the combined measurement was 22.1774 ps. The 0.1987 ps difference shows that the changes were almost additive. U3589xp5 had the same reported physical cell area as U3589xp33 in this library.

Decision: accept both U2467xp67 and U3589xp5. The combined configuration had the best timing, and its entire area cost came from U2467.

#### 6.4.7 U2373: drive the fanout-7 n3095 net

U2373 was changed from NAND2xp33 to NAND2xp5. The larger input increased the n2929 load on U2389, but U2373 and U2525 both became faster.

| Measurement | U2373xp33 | U2373xp5 | Change |
|---|---:|---:|---:|
| n2929 capacitance | 0.8591 | 1.0364 | +0.1773 |
| U2389 delay | 23.6051 ps | 25.5642 ps | +1.9591 ps |
| U2389 output transition | 25.8961 ps | 28.8914 ps | +2.9953 ps |
| U2373 delay | 49.0334 ps | 30.5790 ps | -18.4544 ps |
| U2373 output transition | 87.1396 ps | 46.0851 ps | -41.0545 ps |
| U2525 delay | 27.0728 ps | 21.6974 ps | -5.3754 ps |
| Endpoint arrival | 1182.4242 ps | 1160.2734 ps | -22.1508 ps |
| Path slack | 233.5991 ps | 255.7499 ps | +22.1508 ps |
| Total cell area | 5019.019208 | 5019.019208 | 0 |

Decision: accept U2373xp5. It provided 22.1508 ps of additional path improvement with no measured area increase.

#### 6.4.8 Cumulative result and interpretation

Across the accepted U3908-path sizing sequence, the endpoint arrival improved from 1342.0205 ps to 1160.2734 ps, a cumulative reduction of 181.7471 ps. Slack improved from 74.0028 ps to 255.7499 ps. This cumulative number must not be interpreted as a new whole-design WNS until a fresh unrestricted `report_timing -max_paths 1` is run, because another path can become globally limiting.

The final accepted cells for this route are:

```text
U3734 = OAI21x1
U2467 = NOR2xp67
U3589 = NAND2xp5
U3726 = NOR2xp67
U3733 = NOR2xp67
U3908 = NAND2x1p5
U2373 = NAND2xp5
```

### 6.4.9 Follow-on path: misprediction depth bit 4 to expiring packet [2][0]

After improving the earlier head-pointer route, the investigation was locked to the following exact path so that Design Vision would not silently switch to a different member of the same timing family after each sizing operation:

```text
Startpoint: mispredicted_table_depth_i_reg_reg_4_/QN
Endpoint:   expiring_packet_o_reg_reg_2__0_/D
Anchors:    U2378/Y -> U4276/Y -> U4286/B -> U4286/Y -> U4388/A2
```

The original mapped route used U4276=NOR2xp33 and U4286=NAND2xp5. U4286 drives n3543, which has fanout 28 and 12.3333 units of reported capacitance. U4276 drives U4286 through n3520, so every increase in U4286 drive strength was evaluated together with the extra input-capacitance penalty placed on U4276.

#### U4286 sizing sweep

| U4286 size | Endpoint arrival | Path slack | Total cell area | Timing gain from xp5 | Area increase from xp5 |
|---|---:|---:|---:|---:|---:|
| NAND2xp5 | 1307.3423 ps | 108.6810 ps | 5019.019208 | reference | reference |
| NAND2x1 | 1286.4130 ps | 129.6104 ps | 5019.485768 | 20.9293 ps | +0.466560 |
| NAND2x1p5 | 1269.2488 ps | 146.7745 ps | 5019.952328 | 38.0935 ps | +0.933120 |

For the x1p5 case, the added U4286 input capacitance increased U4276 delay from 77.4522 ps in the original xp5 configuration to 87.5305 ps. Despite that upstream penalty, U4286 delay fell from 104.3513 ps to 65.3575 ps and its output transition improved from 182.3094 ps to 101.6218 ps. The improved slew also reduced delay in the first downstream stages. Decision: retain U4286=NAND2x1p5 provisionally; it provides 38.0935 ps of path improvement for only 0.0186% total-cell-area growth.

#### U4276 sizing with U4286 held at NAND2x1p5

The library does not contain NOR2xp5, so the next available U4276 size above NOR2xp33 was NOR2xp67.

| Measurement | U4276xp33 | U4276xp67 | Change |
|---|---:|---:|---:|
| n3519 capacitance seen by U2378 | 5.3529 | 5.7540 | +0.4011 |
| U2378 delay | 86.5213 ps | 91.2184 ps | +4.6971 ps |
| U2378 output transition | 141.7054 ps | 151.2682 ps | +9.5628 ps |
| U4276 delay | 87.5305 ps | 66.3944 ps | -21.1361 ps |
| U4276 output transition | 106.1195 ps | 71.9336 ps | -34.1859 ps |
| U4286 delay | 65.3575 ps | 55.3774 ps | -9.9801 ps |
| Endpoint arrival | 1269.2488 ps | 1242.8297 ps | -26.4191 ps |
| Path slack | 146.7745 ps | 173.1936 ps | +26.4191 ps |
| Total cell area | 5019.952328 | 5020.418888 | +0.466560 |

The stronger U4276 increased U2378 delay by 4.6971 ps, but reduced its own delay by 21.1361 ps and delivered a much better transition into U4286. That improved U4286 by another 9.9801 ps. The complete locked path therefore improved by 26.4191 ps for approximately 0.0093% additional total cell area. Decision: retain U4276=NOR2xp67 provisionally. Both this choice and U4286=NAND2x1p5 still require unrestricted setup, hold, and design-rule checks before being promoted into the reproducible ECO script.

#### U2378 sizing with U4276=NOR2xp67 and U4286=NAND2x1p5

U2378 drives the fanout-11 n3519 net. It was changed from NOR2xp33 to the next available size, NOR2xp67. The stronger input increased the n3362 load on predecessor U4270, but the improvement propagated through both U4276 and U4286.

| Measurement | U2378xp33 | U2378xp67 | Change |
|---|---:|---:|---:|
| n3362 capacitance seen by U4270 | 1.9310 | 2.3524 | +0.4214 |
| U4270 delay | 20.0389 ps | 22.1946 ps | +2.1557 ps |
| U4270 output transition | 83.5942 ps | 89.6308 ps | +6.0366 ps |
| U2378 delay | 91.2184 ps | 60.1637 ps | -31.0547 ps |
| U2378 output transition | 151.2682 ps | 83.4041 ps | -67.8641 ps |
| U4276 delay | 66.3944 ps | 50.3702 ps | -16.0242 ps |
| U4286 delay | 55.3774 ps | 51.0090 ps | -4.3684 ps |
| Endpoint arrival | 1242.8297 ps | 1193.5381 ps | -49.2916 ps |
| Path slack | 173.1936 ps | 222.4852 ps | +49.2916 ps |
| Total cell area | 5020.418888 | 5020.885448 | +0.466560 |

The U4270 predecessor penalty was only 2.1557 ps. U2378 itself became 31.0547 ps faster and reduced its output transition by 67.8641 ps; this better slew made U4276 16.0242 ps faster and U4286 4.3684 ps faster. The complete locked path improved by 49.2916 ps for approximately 0.0093% additional total cell area. Decision: retain U2378=NOR2xp67 provisionally.

Across the current three-cell sequence—U4286 xp5 to x1p5, U4276 xp33 to xp67, and U2378 xp33 to xp67—the locked endpoint arrival improved from 1307.3423 ps to 1193.5381 ps, a cumulative improvement of 113.8042 ps. Total cell area increased from 5019.019208 to 5020.885448, an increase of 1.866240 or approximately 0.0372%. This cumulative result is specific to the anchored path and must not be treated as whole-design WNS until unrestricted setup and hold reports are rerun.

#### U4270 one-step sizing experiment

With U2378=NOR2xp67, U4276=NOR2xp67, and U4286=NAND2x1p5 held fixed, U4270 was tested from O2A1O1Ixp33 to O2A1O1Ixp5. U4270 was included explicitly as a path anchor so the comparison used the same internal route.

| Measurement | U4270xp33 | U4270xp5 | Change |
|---|---:|---:|---:|
| n3335 capacitance seen by U2860 | 0.5390 | 0.5404 | +0.0014 |
| U2860 delay | 20.6560 ps | 20.6741 ps | +0.0181 ps |
| U4270 delay | 22.1946 ps | 21.5516 ps | -0.6430 ps |
| U4270 output transition | 89.6308 ps | 77.8195 ps | -11.8113 ps |
| U2378 delay | 60.1637 ps | 57.7115 ps | -2.4522 ps |
| U4276 delay | 50.3702 ps | 49.9731 ps | -0.3971 ps |
| U4286 delay | 51.0090 ps | 50.9008 ps | -0.1082 ps |
| Endpoint arrival | 1193.5381 ps | 1189.9802 ps | -3.5579 ps |
| Path slack | 222.4852 ps | 226.0431 ps | +3.5579 ps |
| Total cell area | 5020.885448 | 5021.352008 | +0.466560 |

The predecessor penalty was negligible, but U4270 itself improved by only 0.6430 ps because it was not a major delay contributor. Most of the small endpoint gain came from better slew into U2378. The complete path improved by only 3.5579 ps for the same 0.466560 area increment paid by several much more effective sizing changes. Decision: reject U4270xp5 for the current area-aware ECO set and restore U4270=O2A1O1Ixp33. The result remains documented in case a later near-closure run requires a final few picoseconds and area is secondary.

#### U3735 high-fanout sizing experiment

After restoring U4270 to O2A1O1Ixp33, U3735 was changed from AOI211xp5 to AOI211x1. These are the only two AOI211 strengths available in the loaded ASAP7 library. U3735 drives the fanout-18 n4563 net and was contributing 146.3149 ps with a 290.3343 ps output transition.

| Measurement | U3735xp5 | U3735x1 | Change |
|---|---:|---:|---:|
| n2660 capacitance seen by U3769 | 0.4986 | 0.9392 | +0.4406 |
| U3769 delay | 21.7663 ps | 26.2025 ps | +4.4362 ps |
| U3735 delay | 146.3149 ps | 82.2133 ps | -64.1016 ps |
| U3735 output transition | 290.3343 ps | 152.7220 ps | -137.6123 ps |
| U3818 delay | 57.4758 ps | 44.2052 ps | -13.2706 ps |
| U3819 delay | 26.8508 ps | 26.1483 ps | -0.7025 ps |
| U4267 delay | 39.0851 ps | 33.8336 ps | -5.2515 ps |
| Endpoint arrival | 1193.5381 ps | 1114.6490 ps | -78.8891 ps |
| Path slack | 222.4852 ps | 301.3743 ps | +78.8891 ps |
| Total cell area | 5020.885448 | 5022.285128 | +1.399680 |

The U3769 predecessor penalty was only 4.4362 ps. U3735 itself became 64.1016 ps faster, and the 137.6123 ps slew improvement propagated through U3818 and later decode logic. The complete locked path improved by 78.8891 ps for approximately 0.0279% additional total cell area, or about 56.36 ps of path gain per area unit. Decision: accept U3735=AOI211x1 provisionally.

With U4286=NAND2x1p5, U4276=NOR2xp67, U2378=NOR2xp67, U4270 restored to O2A1O1Ixp33, and U3735=AOI211x1, the locked endpoint arrival improved from 1307.3423 ps to 1114.6490 ps. This is a cumulative path improvement of 192.6933 ps. Total cell area increased from 5019.019208 to 5022.285128, an increase of 3.265920 or approximately 0.0651%. A fresh unrestricted setup/hold analysis is still required before this cumulative result can be interpreted at whole-design level.

#### U2476 sizing experiment

With the preceding accepted changes held fixed, U2476 was changed from NOR2xp33 to NOR2xp67. The loaded library has no NOR2xp5, making xp67 the immediate next available strength. U2476 drives the fanout-7 n2694 net.

| Measurement | U2476xp33 | U2476xp67 | Change |
|---|---:|---:|---:|
| n2683 capacitance seen by U3647 | 1.2949 | 1.6425 | +0.3476 |
| U3647 delay | 31.1305 ps | 34.5019 ps | +3.3714 ps |
| U3647 output transition | 34.8517 ps | 38.7683 ps | +3.9166 ps |
| U2476 delay | 43.9588 ps | 29.8873 ps | -14.0715 ps |
| U2476 output transition | 65.8930 ps | 36.7780 ps | -29.1150 ps |
| U2473 delay | 40.7956 ps | 32.0438 ps | -8.7518 ps |
| U3769 delay | 26.2025 ps | 25.2656 ps | -0.9369 ps |
| Endpoint arrival | 1114.6490 ps | 1094.2013 ps | -20.4477 ps |
| Path slack | 301.3743 ps | 321.8220 ps | +20.4477 ps |
| Total cell area | 5022.285128 | 5022.751688 | +0.466560 |

The stronger U2476 increased U3647 delay by 3.3714 ps, but U2476 itself became 14.0715 ps faster and reduced its output transition by 29.1150 ps. The better slew improved U2473 by 8.7518 ps and U3769 by 0.9369 ps. The complete locked path improved by 20.4477 ps for approximately 0.0093% additional total cell area, or about 43.83 ps of path gain per area unit. Decision: accept U2476=NOR2xp67 provisionally.

After the accepted U4286, U4276, U2378, U3735, and U2476 changes, the locked endpoint arrival improved from 1307.3423 ps to 1094.2013 ps, a cumulative improvement of 213.1410 ps. Total cell area increased from 5019.019208 to 5022.751688, an increase of 3.732480 or approximately 0.0744%.

#### U2369 sizing experiment

U2369 was changed from NOR2xp33 to NOR2xp67, the immediate next available NOR2 strength. It drives the fanout-8 n2728 net. U2476, U3735, U2378, U4276, and U4286 were held at their accepted provisional sizes.

| Measurement | U2369xp33 | U2369xp67 | Change |
|---|---:|---:|---:|
| n2712 capacitance seen by U3756 | 2.4565 | 2.8577 | +0.4012 |
| U3756 delay | 23.8122 ps | 25.4826 ps | +1.6704 ps |
| U3756 output transition | 52.5096 ps | 58.4824 ps | +5.9728 ps |
| U2369 delay | 57.7501 ps | 41.3232 ps | -16.4269 ps |
| U2369 output transition | 84.2757 ps | 49.8100 ps | -34.4657 ps |
| U3647 delay | 34.5019 ps | 26.5758 ps | -7.9261 ps |
| U2476 delay | 29.8873 ps | 27.5809 ps | -2.3064 ps |
| Endpoint arrival | 1094.2013 ps | 1069.2117 ps | -24.9896 ps |
| Path slack | 321.8220 ps | 346.8116 ps | +24.9896 ps |
| Total cell area | 5022.751688 | 5023.218248 | +0.466560 |

The U3756 predecessor penalty was 1.6704 ps. U2369 became 16.4269 ps faster and reduced its output transition by 34.4657 ps; the better slew improved U3647 by 7.9261 ps and U2476 by 2.3064 ps. The complete locked path improved by 24.9896 ps for approximately 0.0093% additional total cell area, or about 53.56 ps of path gain per area unit. Decision: accept U2369=NOR2xp67 provisionally.

After the accepted U4286, U4276, U2378, U3735, U2476, and U2369 changes, the locked endpoint arrival improved from 1307.3423 ps to 1069.2117 ps, a cumulative improvement of 238.1306 ps. Total cell area increased from 5019.019208 to 5023.218248, an increase of 4.199040 or approximately 0.0837%.

#### U3756 rejected sizing experiment

U3756 was tested from OAI21xp5 to OAI21x1 because the loaded library provides no intermediate OAI21xp67 cell. The stronger cell improved its own delay and output slew, but its substantially larger input capacitance loaded two upstream portions of the active path.

| Measurement | U3756xp5 | U3756x1 | Change |
|---|---:|---:|---:|
| n2641 capacitance driven by U3754 | 1.0643 | 1.6873 | +0.6230 |
| U3754 delay | 36.2623 ps | 44.7596 ps | +8.4973 ps |
| n2640 capacitance driven by U3755 | 0.5737 | 1.2446 | +0.6709 |
| U3755 delay | 22.9838 ps | 33.9765 ps | +10.9927 ps |
| U3756 delay | 25.4826 ps | 21.4523 ps | -4.0303 ps |
| U3756 output transition | 58.4824 ps | 37.7280 ps | -20.7544 ps |
| U2369 delay | 41.3232 ps | 35.3534 ps | -5.9698 ps |
| U3647 delay | 26.5758 ps | 25.7299 ps | -0.8459 ps |
| U2476 delay | 27.5809 ps | 27.3398 ps | -0.2411 ps |
| Endpoint arrival | 1069.2117 ps | 1077.6146 ps | +8.4029 ps |
| Path slack | 346.8116 ps | 338.4087 ps | -8.4029 ps |
| Total cell area | 5023.218248 | 5023.918088 | +0.699840 |

The local U3756 and downstream gains totaled less than the 19.4900 ps combined upstream penalty at U3754 and U3755. The complete path became 8.4029 ps slower while area increased by 0.699840. Decision: reject U3756=OAI21x1 and restore U3756=OAI21xp5.

### 6.4.10 Follow-on path: en_i to expiring packet [3][0]

After completing the misprediction-depth path experiments, the unrestricted maximum-delay report selected an input-to-register path from `en_i` to `expiring_packet_o_reg_reg_3__0_/D`. The 700 MHz constraint assigns 857.1430 ps, or 60% of the clock period, to external input delay. The original mapped path arrived at 1296.7107 ps with 119.3126 ps of slack, leaving 439.5677 ps of internal combinational delay.

The exact mapped path was:

```text
en_i
  -> U2355 NAND2x1
  -> n2663, fanout 57
  -> U2354 INVx1
  -> n2627, fanout 64
  -> U2382 NAND2xp33
  -> n3775, fanout 7
  -> U4457 A2O1A1Ixp33
  -> expiring_packet_o_reg_reg_3__0_/D
```

The path was correlated with the RTL-planning schematic rather than treated as an isolated gate chain. U3747 and U3748 reconstruct `input_stage_valid_reg && br_valid_i_reg && !recovery_active_i_reg`, which is the RTL `br_valid_and_recovery_not_active` condition. U2355 combines that condition with raw `en_i`, and U2354 distributes the resulting active-high qualified enable. U2382 reconverges this control with an address/read-selection term derived from misprediction depth and the target-index/read-bank/read-row cone. Its fanout-seven output supplies shared control to the seven packet bits of history-depth entry 3. U4457 is the final bit-specific output-selection cell.

The output-register hold path was also traced explicitly:

```text
expiring_packet_o_reg_reg_3__0_/QN
  -> U3698
  -> expiring_packet_o[21]
  -> U4456/B2
  -> U4456/Y
  -> U4457/C
  -> U4457/Y
  -> expiring_packet_o_reg_reg_3__0_/D
```

This feedback path arrived in 140.9549 ps with 1274.1711 ps of slack, proving that register hold feedback was not the limiter. The optimization effort therefore remained on the high-fanout `en_i` distribution path.

#### U2354 inverter sizing

U2354 was changed from INVx1 to INVx2. U2355 remained NAND2x1 for this comparison.

| Measurement | U2354=INVx1 | U2354=INVx2 | Change |
|---|---:|---:|---:|
| U2355 delay | 131.4839 ps | 133.7222 ps | +2.2383 ps |
| U2354 delay | 164.6942 ps | 114.7085 ps | -49.9857 ps |
| U2382 delay | 117.9811 ps | 96.6190 ps | -21.3621 ps |
| U4457 delay | 25.4086 ps | 24.4424 ps | -0.9662 ps |
| Endpoint arrival | 1296.7107 ps | 1226.6351 ps | -70.0756 ps |
| Path slack | 119.3126 ps | 189.4263 ps | +70.1137 ps |
| Total cell area | 5023.218248 | 5023.451528 | +0.233280 |

The larger inverter increased U2355 delay by only 2.2383 ps while reducing its own delay by 49.9857 ps. Its improved output slew also reduced U2382 delay by 21.3621 ps. The internal combinational portion improved by 70.0756 ps, or approximately 15.94%, for approximately 0.0046% additional total cell area. Decision: retain U2354=INVx2 provisionally.

#### U2355 NAND sizing sweep

With U2354 held at INVx2, U2355 was evaluated at NAND2x1, NAND2x1p5, and NAND2x2.

| U2355 version | Endpoint arrival | Path slack | Total cell area |
|---|---:|---:|---:|
| NAND2x1 | 1226.6351 ps | 189.4263 ps | 5023.451528 |
| NAND2x1p5 | 1151.1943 ps | 265.0264 ps | 5023.918088 |
| NAND2x2 | 1132.0619 ps | 284.2445 ps | 5024.384648 |

Moving from NAND2x1 to NAND2x1p5 improved endpoint arrival by 75.4408 ps for 0.466560 additional area. Moving from NAND2x1p5 to NAND2x2 produced another 19.1324 ps of endpoint improvement and another 0.466560 area increment. Relative to NAND2x1, NAND2x2 improved the path by 94.5732 ps while increasing total cell area by 0.933120, approximately 0.0186%.

The U2355/A predecessor was checked separately because that input is driven by U3748, whereas U2355/B is driven directly by the constrained `en_i` port. U3748 delay changed from 25.5062 ps with NAND2x1 to 26.3671 ps with NAND2x1p5 and 27.1302 ps with NAND2x2. The additional predecessor penalty from x1p5 to x2 was only 0.7631 ps. Over the same step, the complete supporting path from `input_stage_valid_reg_reg/QN` improved from 385.7112 ps to 367.9107 ps, and its slack improved from 1030.5095 ps to 1048.3958 ps. Thus, the larger NAND improved both relevant paths rather than shifting the bottleneck upstream.

Decision: retain U2355=NAND2x2 provisionally. NAND2x1p5 was the more area-efficient first step, but NAND2x2 was selected because it delivered another 19.1324 ps on the limiting path, improved the supporting registered-control path by 17.8005 ps, imposed only a 0.7631 ps incremental predecessor penalty, and cost only 0.466560 additional area.

Across the accepted U2354 and U2355 changes, endpoint arrival improved from 1296.7107 ps to 1132.0619 ps, a cumulative gain of 164.6488 ps. Path slack increased from 119.3126 ps to 284.2445 ps. Total cell area increased from 5023.218248 to 5024.384648, an increase of 1.166400 or approximately 0.0232%. These results apply to the locked path; unrestricted setup, hold, design-rule, and PrimeTime checks remain required before treating the result as a new whole-design frequency limit.

#### U2382 NAND sizing sweep

With U2354=INVx2 and U2355=NAND2x2 held fixed, U2382 was evaluated at NAND2xp33, NAND2xp5, and NAND2xp67. U2382 is a reconvergence point: input A is driven by the high-fanout qualified-enable net from U2354, while input B is driven by U3497 in the misprediction-depth/target-index/read-selection cone. Both predecessor paths were checked before accepting a size.

| U2382 version | Main-path arrival | Main-path slack | Total cell area |
|---|---:|---:|---:|
| NAND2xp33 | 1132.0619 ps | 284.2445 ps | 5024.384648 |
| NAND2xp5 | 1101.4697 ps | 314.8352 ps | 5024.384648 |
| NAND2xp67 | 1104.9497 ps | 311.3529 ps | 5024.851208 |

Changing from xp33 to xp5 improved the main path by 30.5922 ps without increasing reported cell area. U2354, the input-A predecessor, slowed by only 0.2571 ps. U2382 itself improved by 27.3053 ps, its output transition improved from 123.6426 ps to 73.7299 ps, and the improved slew reduced U4457 delay by another 3.5440 ps.

The input-B supporting path also improved. U3497 incurred a 2.1669 ps predecessor penalty, but U2382 improved by 10.4348 ps and U4421 improved by 6.5514 ps. Supporting-path arrival decreased from 973.3538 ps to 958.5346 ps, a gain of 14.8192 ps, while slack increased from 441.7723 ps to 457.4533 ps.

Increasing U2382 again from xp5 to xp67 was counterproductive on the limiting path. U2354 delay increased from 85.5914 ps to 85.9989 ps, U2382 delay increased from 61.1125 ps to 63.9775 ps, and U4457 delay increased from 20.6118 ps to 20.8193 ps. Endpoint arrival therefore worsened by 3.4800 ps, slack decreased by 3.4823 ps, and total cell area increased by 0.466560. The nominally stronger cell is not guaranteed to be faster for every characterized input slew, output load, and timing arc; in this operating region, NAND2xp5 is the better library choice.

Decision: reject U2382=NAND2xp67, restore U2382=NAND2xp5, and retain xp5 provisionally. Relative to the original xp33 mapping, xp5 improves both predecessor routes, provides 30.5922 ps on the limiting path and 14.8192 ps on the supporting path, and carries no reported area penalty.

After the accepted U2354, U2355, and U2382 changes, locked-path arrival is 1101.4697 ps, a cumulative improvement of 195.2410 ps from the 1296.7107 ps starting point. Locked-path slack is 314.8352 ps. Total cell area remains 5024.384648, an increase of 1.166400 or approximately 0.0232% over the start of this path investigation.

### 6.5 Reproducing and preserving the mapped-cell choices

The previously accepted changes are implemented by `scripts/ghr/ghr_2reg_700mhz_manual_sizing_eco.tcl`. The newly selected U2354=INVx2, U2355=NAND2x2, and U2382=NAND2xp5 choices remain provisional in the current Design Vision session and must be added to that ECO script after the present path sweep and unrestricted timing checks are complete. The synthesis script sources the ECO after `compile_ultra` and before final checks, reports, and netlist writes. Applying the ECO before `compile_ultra` would not preserve the choices because compile optimization is free to remap the cells.

The ECO deliberately checks that each generated instance name resolves to exactly one cell and that every requested library cell exists. It stops the run if the mapping changes. This is necessary because names such as U3734 and U3908 are generated netlist names, not stable RTL instance names.

After sizing, the accepted cells are marked `dont_touch` and timing is updated. The resulting DDC is the reopenable mapped checkpoint; the ECO Tcl file is the reproducible record of how that checkpoint was produced. If RTL, SDC constraints, library revisions, or the synthesis tool version changes, the mapping must be re-characterized instead of blindly renaming new cells to match this list.
## 7. Constraints and signoff caveats

The 700 MHz run uses 60% of the period as maximum input delay and 40% as maximum output delay. No clock uncertainty is currently applied. rst_n is an asynchronous reset and is false-pathed from synchronous data-path analysis.

PrimeTime analysis coverage reports 664 of 2656 setup checks and 664 of 2656 hold checks as tested. The untested checks are primarily constant-disabled asynchronous reset/preset, recovery, removal, and pulse-width arcs. This does not invalidate the reported synchronous critical path, but reset recovery/removal must be handled separately before physical signoff.

## 8. Reproducible artifacts

- RTL: Verification/Verification Block Level/GHR_2reg/1_LP_Global_Histroy_register_2reg.sv
- UVM testbench: Verification/Verification Block Level/GHR_2reg/TB_GHR_2reg.sv
- Verification plan: Verification/Verification Block Level/GHR_2reg/verification plan doc.docx
- 700 MHz SDC: constraints/ghr/LP_ghr_block_2reg_700mhz.sdc
- Design Compiler script: scripts/ghr/synthesize_ghr_2reg_700mhz.tcl
- PrimeTime script: scripts/ghr/primetime_ghr_2reg_700mhz.tcl
- PrimeTime reports: reports/ghr/primetime_2reg_700mhz/
- DC report summary: reports/ghr/dc_2reg_700mhz/README.md

The scripts expect the ASAP7 .db libraries under lib/asap7_db. The Design Compiler script reads the registered-I/O RTL from the repository verification directory and writes the synthesized netlist under netlist; the PrimeTime script consumes that netlist and generated SDC.
