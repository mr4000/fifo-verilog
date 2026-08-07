`timescale 1ns / 1ps
module fifo_async #(
  parameter WIDTH = 8,
  parameter DEPTH = 16
)(
  // Write side (producer)
  input  wire                 wr_clk,
  input  wire                 wr_rst_n,   // async active-low reset
  input  wire                 wr_en,
  input  wire [WIDTH-1:0]     wr_data,
  output wire                 full,

  // Read side (consumer)
  input  wire                 rd_clk,
  input  wire                 rd_rst_n,   // async active-low reset
  input  wire                 rd_en,
  output reg  [WIDTH-1:0]     rd_data,
  output wire                 empty
);

  // 1) Local params
  localparam ASIZE = $clog2(DEPTH);
  localparam P = ASIZE + 1;
  localparam DEPTH_L = (1 << ASIZE);

  // -------------------------------------------------------------------
  // storage: inference-friendly dual-clock memory
  // -------------------------------------------------------------------
  reg [WIDTH-1:0] mem [0:DEPTH_L-1];

  // -------------------------------------------------------------------
  // pointers and addresses (write & read side)
  // -------------------------------------------------------------------
  // Write-side
  reg  [P-1:0] wr_bin;      // binary write pointer (local)
  reg  [P-1:0] wr_gray;     // Gray-coded write pointer (registered)
  wire [P-1:0] wbin_next;   // combinational next binary
  wire [P-1:0] wgnext;      // combinational next Gray
  wire [ASIZE-1:0] waddr = wr_bin[ASIZE-1:0];

  // Read-side
  reg  [P-1:0] rd_bin;      // binary read pointer (local)
  reg  [P-1:0] rd_gray;     // Gray-coded read pointer (registered)
  wire [P-1:0] rbin_next;   // combinational next binary
  wire [P-1:0] rgnext;      // combinational next Gray
  wire [ASIZE-1:0] raddr = rd_bin[ASIZE-1:0];

  // -------------------------------------------------------------------
  // 2-FF vector synchronizers (per-domain)
  // -------------------------------------------------------------------
  reg [P-1:0] wrptr_s1, wrptr_s2;  // rd_gray sampled into write domain
  reg [P-1:0] rwptr_s1, rwptr_s2;  // wr_gray sampled into read domain

  wire [P-1:0] wrptr_sync = wrptr_s2;
  wire [P-1:0] rwptr_sync = rwptr_s2;

  // -------------------------------------------------------------------
  // Gray/Binary conversion functions (P-bit)
  // -------------------------------------------------------------------
  function [P-1:0] bin2gray;
    input [P-1:0] b;
    integer i;
    begin
      bin2gray[P-1] = b[P-1];
      for (i = P-2; i >= 0; i = i-1)
        bin2gray[i] = b[i+1] ^ b[i];
    end
  endfunction

  function [P-1:0] gray2bin;
    input [P-1:0] g;
    integer j;
    begin
      gray2bin[P-1] = g[P-1];
      for (j = P-2; j >= 0; j = j-1)
        gray2bin[j] = gray2bin[j+1] ^ g[j];
    end
  endfunction

  // -------------------------------------------------------------------
  // Next-pointer combinational logic (use registered full/empty for gating)
  // -------------------------------------------------------------------
  assign wbin_next = wr_bin + (wr_en & ~full); // if (!full)
                                             // wptr <= wptr + 1;
  assign wgnext    = bin2gray(wbin_next);

  assign rbin_next = rd_bin + (rd_en & ~empty);
  assign rgnext    = bin2gray(rbin_next);

  // -------------------------------------------------------------------
  // MEMORY write: do the write at wclk using current write address (wr_bin)
  // We must only write when wr_en and not full (safety).
  // Use registered full to gate.
  // -------------------------------------------------------------------
  always @(posedge wr_clk) begin
    if (wr_en && !full) begin
      mem[waddr] <= wr_data;
    end
  end

  // read port: synchronous registered read output on rd_clk
  always @(posedge rd_clk) begin
    rd_data <= mem[raddr];
  end

  // -------------------------------------------------------------------
  // Write-side sequential: sync rptr into write domain, update wbin/wr_gray, produce wfull
  // STA-friendly: wfull compares next Gray (wgnext) to synchronized rptr (wrptr_sync)
  // -------------------------------------------------------------------
  reg wfull_reg;
  always @(posedge wr_clk or negedge wr_rst_n) begin
    if (!wr_rst_n) begin
      wr_bin    <= {P{1'b0}};
      wr_gray   <= {P{1'b0}};
      wfull_reg <= 1'b0;
      wrptr_s1  <= {P{1'b0}};
      wrptr_s2  <= {P{1'b0}};
    end else begin
      // sync read pointer into write domain
      wrptr_s1 <= rd_gray;
      wrptr_s2 <= wrptr_s1;

      // update local binary and gray pointers
      wr_bin  <= wbin_next;
      wr_gray <= wgnext;

      // STA-friendly full: compare next Gray pointer to synchronized remote read pointer
       wfull_reg <= (wgnext == {~wrptr_sync[P-1:P-2], wrptr_sync[P-3:0]});
    end
  end
  assign full = wfull_reg;

  // -------------------------------------------------------------------
  // Read-side sequential: sync wptr into read domain, update rbin/rd_gray, produce rempty
  // STA-friendly: rempty compares next Gray (rgnext) to synchronized wptr (rwptr_sync)
  // -------------------------------------------------------------------
  reg rempty_reg;
  always @(posedge rd_clk or negedge rd_rst_n) begin
    if (!rd_rst_n) begin
      rd_bin    <= {P{1'b0}};
      rd_gray   <= {P{1'b0}};
      rempty_reg<= 1'b1;
      rwptr_s1  <= {P{1'b0}};
      rwptr_s2  <= {P{1'b0}};
    end else begin
      // sync write pointer into read domain
      rwptr_s1 <= wr_gray;
      rwptr_s2 <= rwptr_s1;

      // update local binary and gray pointers
      rd_bin  <= rbin_next;
      rd_gray <= rgnext;

      // STA-friendly empty: compare next Gray pointer to synchronized remote write pointer
      rempty_reg <= (rgnext == rwptr_sync);
    end
  end
  assign empty = rempty_reg;

endmodule
