# 📘 Asynchronous FIFO – Theory, Design & Verification

This document explains the theory, architecture, and verification of an **asynchronous FIFO**, focusing on safe data transfer between **independent clock domains**.

---

# 1. Asynchronous FIFO Theory

An **asynchronous FIFO** transfers data between two unrelated clocks:

- **Write clock:** `wr_clk`
- **Read clock:** `rd_clk`

It must safely manage:

- Metastability  
- Pointer corruption  
- Safe multi-bit synchronization  
- Reliable FULL/EMPTY detection  
- Overflow/Underflow protection  

This design uses the **standard industry architecture**.

---

## 1.1 Why Use Gray-Code Pointers?

Binary counters may change multiple bits at once:

```
0111 → 1000   // 4 bits change
```

If sampled mid-transition, another clock domain sees **corrupted values**.

### ✔ Gray code solves this

- Only **one bit changes per count**
- Cross-domain sampling has at most **1 bit uncertainty**
- FULL/EMPTY logic becomes safe

Example Gray sequence:

```
0110 → 0111 → 0101 → 0100 → 1100 → ...
```

---

## 1.2 Pointer Width & Structure

For FIFO depth:

```
DEPTH = 2^ASIZE
```

Pointer width:

```
P = ASIZE + 1  // extra MSB for wrap detection
```

| Purpose                     | Format |
|-----------------------------|--------|
| Addressing & incrementing   | Binary |
| Crossing clock domains (CDC) | Gray   |

Lower ASIZE bits → memory address  
MSB → wrap detection

---

## 1.3 Pointer Synchronizers (CDC)

Each pointer crosses to the opposite domain using **two flip-flops**:

```verilog
// Read pointer → write clock domain
wrptr_s1 <= rd_gray;
wrptr_s2 <= wrptr_s1;

// Write pointer → read clock domain
rwptr_s1 <= wr_gray;
rwptr_s2 <= rwptr_s1;
```

Only the **second stage** is used (`*_s2`), removing metastability and ensuring stable pointer values.

---

## 1.4 Next-Pointer Logic (STA Friendly)

```verilog
wbin_next = wr_bin + (wr_en & ~full);
wgnext    = bin2gray(wbin_next);

rbin_next = rd_bin + (rd_en & ~empty);
rgnext    = bin2gray(rbin_next);
```

Using *next* values ensures FULL/EMPTY flags update immediately.

---

## 1.5 FULL Condition (Gray Logic)

```verilog
wfull_reg <= (wgnext == {~wrptr_sync[P-1:P-2], wrptr_sync[P-3:0]});
```

### Why invert the top two bits?

- When the write pointer wraps and catches the read pointer  
- The Gray codes differ only in their MSBs  
- This detects **true FIFO FULL**

This is the standard industry formula.

---

## 1.6 EMPTY Condition

```verilog
rempty_reg <= (rgnext == rwptr_sync);
```

When next read pointer equals synchronized write pointer → FIFO empty.

---

## 1.7 Memory Behavior

### Write (write-clock domain)

```verilog
if (wr_en && !full)
    mem[waddr] <= wr_data;
```

### Read (read-clock domain)

```verilog
rd_data <= mem[raddr];
```

The output holds stable when empty = 1.

---

## 1.8 Why FIFO Depth Must Be Power-of-2

Gray code wraps correctly only for **2ⁿ sized FIFOs**.  
Non-power-of-2 depths violate the one-bit transition property and break CDC safety.

---

# 2. Testbench Description

The testbench provides full verification of the FIFO design.

---

## 2.1 Reset Handling (Vivado GSR)

Vivado introduces a **Global Set/Reset (GSR)** active for ~100 ns during post-implementation simulation.

Testbench waits:

```
#200;
wr_rst_n = 1;
rd_rst_n = 1;
```

This ensures the FIFO internal registers are not held by GSR.

---

## 2.2 Clock Generation

- Write clock: `wr_clk = 100 MHz` (10 ns)  
- Read clock: `rd_clk ≈ 71 MHz` (14 ns)

These independent clocks cause *true asynchronous* operation.

---

## 2.3 Writing Until FULL

```verilog
wcount = 0;
wr_en = 1;

while (!full) begin
    wr_data = wcount[7:0];
    @(posedge wr_clk);
    $display("[WR] t=%0t  WROTE %0d", $time, wr_data);
    wcount = wcount + 1;
end

wr_en = 0;
```

---

## 2.4 Illegal Write Test (Overflow Prevention)

After FIFO becomes FULL:

```verilog
wr_en  = 1;
wr_data = 8'hAA;
```

But because:

```verilog
if (wr_en && !full)
```

Write is **ignored** → confirms overflow protection.

---

## 2.5 Reading Until EMPTY

```verilog
rd_en = 1;
while (!empty) @(posedge rd_clk);
rd_en = 0;
```

FIFO drains completely → EMPTY asserted correctly.

---

# 3. Output Waveforms (Post-Implementation)

Waveforms are stored in the **Outputwaveform** directory.

### 🔹 Full Condition  
**Click to open:**  
[Full_condition.png](Outputwaveform/Full_condition.png)

### 🔹 Empty Condition  
**Click to open:**  
[Empty_condition.png](Outputwaveform/Empty_condition.png)


---

# 4. Summary

This project demonstrates a fully functional asynchronous FIFO featuring:

- Gray-code pointers  
- Dual clock domains  
- Safe pointer synchronization  
- Correct FULL and EMPTY detection  
- Overflow & underflow protection  

Verification performed via:

- Behavioral simulation  
- Post-synthesis simulation  
- Post-implementation timing simulation  

This design represents the **canonical industry-standard FIFO architecture** for CDC applications.

# 5.Misc
### Why non-power-of-two depths are difficult in asynchronous FIFOs

The issue is **not the pointer width**. Both `DEPTH=16` and `DEPTH=13` use:

- `ASIZE = ceil(log2(DEPTH)) = 4`
- 5-bit pointers (4 address bits + 1 wrap bit)

The problem is the **pointer state space**.

- **DEPTH = 16:** A 5-bit pointer naturally cycles through `32` states (`0..31`), and `2 × DEPTH = 32`. Binary overflow works naturally, and standard Gray coding preserves the **one-bit transition** property, even at wrap:

```
Binary : 11111 (31) -> 00000 (0)
Gray   : 10000      -> 00000
                  ^ Only one bit changes
```

- **DEPTH = 13:** A 5-bit pointer still cycles through `32` states, but only `2 × DEPTH = 26` states are valid (`0..25`). The pointer must be forced to wrap:

```systemverilog
if (ptr == 25)
    ptr <= 0;
else
    ptr <= ptr + 1;
```

The forced wrap breaks the Gray-code property:

```
Binary : 11001 (25) -> 00000 (0)
Gray   : 10101      -> 00000
         ^ ^ ^
         3 bits change
```

Since asynchronous FIFOs rely on **only one Gray-code bit changing between consecutive pointer values** for safe clock-domain crossing, the standard Gray-pointer synchronization no longer works.

Hence, standard asynchronous FIFOs assume a **power-of-two depth**. For non-power-of-two depths, either:
- allocate the next power-of-two memory and ignore the extra locations (industry standard), or
- use a custom pointer encoding.


