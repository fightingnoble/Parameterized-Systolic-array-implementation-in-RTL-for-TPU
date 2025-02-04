Parameterized Systolic Array Accelerator Design
Modified from [Systolic-array-implementation-in-RTL-for-TPU](https://github.com/abdelazeem201/Systolic-array-implementation-in-RTL-for-TPU)


### 1. 数据预处理与结果后处理  

#### a. **数据准备**  
首先，我们使用 Python 脚本 `benchmarkgen.py` 生成基准测试数据。该脚本：  
- 创建形状为 `[batch_size, row_size, col_size]` 的矩阵 **A** 和 **B**。  
- 计算每个批次的矩阵 **A** 和 **B** 的点积 **C**。  
- 指定矩阵的位精度：**A** 的精度为 `A_nbits`，**B** 的精度为 `B_nbits`，点积 **C** 的精度为 `C_nbits`。  

生成的数据以二进制字符串的形式存储在目录 `bm/bmy/` 中，包含以下文件：  
- **`mat1.txt`/`mat2.txt`**：矩阵 **A**/**B** 的二进制表示。  
  - 每个文件包含 `batch_size × row_size` 行。  
  - 每行包含 `col_size × nbits` 位。  
  - 在每行中，最高 `nbits` 位对应 `A[batch_idx×row_size + row_idx, 0]`，最低 `nbits` 位对应 `A[batch_idx×row_size + row_idx, col_size-1]`。  

- **`goldenx.txt`**：点积 **C** 的二进制表示（用于验证）。  
  - 格式与 `mat1.txt` 和 `mat2.txt` 相同。  

---

#### b. **数据预处理**  
Verilog 模块 `test_tpu.v` 执行以下预处理步骤：  

- **对于 `mat1.txt`/`mat2.txt`：**  
  1. **读取与转换**：从文件中读取二进制字符串并将其转换为整数。  
  2. **批次合并**：将矩阵从 `[BATCH_SIZE×row_size, col_size×data_width]` 重塑为 `[array_size, BATCH_SIZE×array_size×data_width]`。  
  3. **填充以对齐时序**：  
     - 为了与脉动阵列的时序同步，将每行填充为平行四边形形状。  
     - 对于第 `i` 行：  
       - 在行的**右侧**填充 `i` 个零。  
       - 在行的**左侧**填充 `(array_size - 1 - i)` 个零。  
  4. **SRAM 存储体打包**：  
     - 由于 SRAM 数据宽度为 32 位，每 **4 行**数据被打包到一个 SRAM 存储体中。  
     - 最终维度为 `[(BATCH_SIZE×array_size + 3), sram_data_width]`。  

- **对于 `goldenx.txt`：**  
  - 将点积结果从 `[row_size, col_size]` 重塑为 `[2×array_size - 1, array_size]`。  
  - 第 `k` 行包含满足 `i + j = k` 的元素 `C[i,j]`，未使用的位置填充零。  

---

#### c. **结果后处理**  
- 将每个处理单元（PE）的输出与 `goldenx.txt` 中的参考值进行**逐周期比较**。  

---

### 主要改进：  
1. **语法与标点**：  
   - 修正了缺少空格的问题（如 `Bwith` → `B with`，`Thier` → `Their`）。  
   - 补充了必要的冠词（如 "点积" → "**的**点积"）。  
   - 统一了动词时态（如 "计算" → "计算"）。  

2. **技术细节清晰度**：  
   - 将模糊的术语（如 "大小"）替换为更明确的表达（如 "右侧"）。  
   - 明确了维度与重塑逻辑（如 `[BATCH_SIZE×row_size, ...]`）。  
   - 标准化了符号表示（如 `nbits` → `nbits`）。  

3. **格式优化**：  
   - 统一了术语（如 "SRAM 存储体" 替代 "SRAM 数据存储体"）。  
   - 改进了层次结构，提升可读性。  

--- 

希望这个版本更符合你的需求！如果还有其他问题，欢迎随时提出。