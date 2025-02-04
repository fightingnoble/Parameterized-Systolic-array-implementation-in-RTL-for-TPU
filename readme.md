Parameterized Systolic Array Accelerator Design
Modified from [Systolic-array-implementation-in-RTL-for-TPU](https://github.com/abdelazeem201/Systolic-array-implementation-in-RTL-for-TPU)

## generate the benchmark data
python benchmarkgen.py --array_size 8 --output_dir bm/bm1
python benchmarkgen.py --array_size 16 --output_dir bm/bm2
python benchmarkgen.py --array_size 32 --output_dir bm/bm3

## test_tpu.v 

### 1. Preprocess the Data and Postprocess the Results  

#### a. **Data Preparation**  
First, we use the Python script `benchmarkgen.py` to generate benchmark data. This script:  
- Creates matrices **A** and **B** with shapes `[batch_size, row_size, col_size]`.  
- Computes the dot product of **A** and **B** for each batch.  
- Specifies bit precisions for the matrices: `A_nbits`, `B_nbits`, and `C_nbits` for **A**, **B**, and their product **C**, respectively.  

The generated data is stored as binary strings in the directory `bm/bmy/` with the following files:  
- **`mat1.txt`/`mat2.txt`**: Binary representations of matrices **A**/**B**.  
  - Each file contains `batch_size × row_size` rows.  
  - Each row consists of `col_size × nbits` bits.  
  - Within a row, the highest `nbits` bits correspond to `A[batch_idx×row_size + row_idx, 0]`, while the lowest `nbits` bits correspond to `A[batch_idx×row_size + row_idx, col_size-1]`.  

- **`goldenx.txt`**: Binary representation of the dot product **C** (for validation).  
  - Follows the same format as `mat1.txt` and `mat2.txt`.  

---

#### b. **Data Preprocessing**  
The Verilog module `test_tpu.v` performs preprocessing as follows:  

- **For `mat1.txt`/`mat2.txt`:**  
  1. **Read & Convert**: Read binary strings from files and convert them to integers.  
  2. **Batch Combination**: Reshape the matrices from `[BATCH_SIZE×row_size, col_size×data_width]` to `[array_size, BATCH_SIZE×array_size×data_width]`.  
  3. **Padding for Timing Alignment**:  
     - To synchronize with the systolic array’s timing, each row is padded into a parallelogram shape.  
     - For the `i`-th row:  
       - Pad `i` zeros to the **right side** of the row.  
       - Pad `(array_size - 1 - i)` zeros to the **left side** of the row.  
  4. **SRAM Bank Packing**:  
     - Since SRAM data width is 32 bits, every **4 rows** are packed into one SRAM bank.  
     - Final dimensions: `[(BATCH_SIZE×array_size + 3), sram_data_width]`.  

- **For `goldenx.txt`:**  
  - Reshape the dot product result from `[row_size, col_size]` to `[2×array_size - 1, array_size]`.  
  - The `k`-th row contains elements `C[i,j]` where `i + j = k`, with unused positions filled with zeros.  

---

#### c. **Result Postprocessing**  
- The outputs from each processing element (PE) are **cycle-by-cycle compared** against the reference values in `goldenx.txt`.  

