import numpy as np
import os

def generate_matrices(array_size, A_nbit, B_nbit, C_nbit, batch_size):
    """
    生成两个 [batch_size, array_size, array_size] 的整数矩阵，
    矩阵元素为 nbit 比特有符号随机整数。
    """
    # 生成随机整数矩阵
    # mat1=[[\
    # [-81,-98,110,-97,14,-7,-65,-71],
    # [-1,81,-76,-32,72,-47,-62,1],
    # [-6,-53,64,23,43,27,-103,114],
    # [-46,-85,-3,-16,-25,-49,-81,-3],
    # [-117,-25,51,123,58,103,70,-91],
    # [55,120,115,-82,13,-62,7,36],
    # [-14,-109,-92,-27,-56,-81,99,5],
    # [6,-5,0,-79,-34,-15,20,-14],
    # ],[\
    # [-119,-75,-77,108,-119,28,-94,-26],
    # [-26,-71,-67,56,-7,-57,112,122],
    # [-105,6,-63,-83,-127,70,-72,46],
    # [-47,116,-1,101,-76,19,34,-2],
    # [122,-47,-38,-33,21,-23,-76,-105],
    # [-128,-8,64,88,95,1,123,116],
    # [118,69,97,-77,-106,72,-94,-119],
    # [68,-106,100,34,92,99,-15,-106],
    # ],[\
    # [44,34,-102,27,-62,27,38,-15],
    # [83,-119,-78,22,33,104,-111,-11],
    # [105,-40,115,34,41,99,-100,0],
    # [19,-20,126,-111,101,1,55,-43],
    # [60,92,-77,-85,48,-17,-27,20],
    # [61,-85,117,-20,112,3,-54,-22],
    # [59,68,31,72,62,62,-9,-31],
    # [116,87,27,-128,20,-1,107,108],
    # ]]

    # mat2=[[\
    # [99,-48,77,-60,109,-101,37,102],
    # [-93,123,-89,15,22,13,-65,-75],
    # [117,33,28,-120,-82,66,53,-61],
    # [8,95,-113,-79,100,48,-113,-112],
    # [104,125,-122,89,-66,12,118,-107],
    # [46,-111,23,-109,104,97,-19,15],
    # [-41,94,19,20,17,93,107,118],
    # [106,-3,109,61,5,-59,119,68],
    # ],[\
    # [-58,-81,-82,-5,-115,-4,35,-71],
    # [36,53,84,-66,93,77,-8,-18],
    # [7,73,25,-106,-43,-65,-63,59],
    # [-53,123,76,-43,-58,-32,73,-14],
    # [-15,102,-17,14,-100,-75,111,-14],
    # [-36,100,-119,-94,-77,-36,-17,98],
    # [-101,-32,103,-79,-5,107,-90,21],
    # [-124,-104,-87,10,31,42,-116,51],
    # ],[\
    # [28,-1,37,-65,-84,-119,24,57],
    # [10,96,-102,92,-128,-118,92,-66],
    # [-92,-41,18,52,-112,68,-47,103],
    # [44,117,-2,52,89,37,73,-55],
    # [-80,-27,-47,-15,-33,-45,-37,4],
    # [-73,119,-63,-38,66,117,-38,-21],
    # [68,90,-68,-88,90,58,-54,112],
    # [-70,86,14,22,1,-128,-60,124],
    # ]]
    # mat1 = np.array(mat1, dtype=np.int32)
    # mat2 = np.array(mat2, dtype=np.int32)
    mat1 = np.random.randint(-2**(A_nbit-1), 2**(A_nbit-1)-1, size=(batch_size, array_size, array_size), dtype=np.int32)
    mat2 = np.random.randint(-2**(B_nbit-1), 2**(B_nbit-1)-1, size=(batch_size, array_size, array_size), dtype=np.int32)
    result = np.matmul(mat1, mat2.transpose((0, 2, 1))).clip(-2**(C_nbit-1), 2**(C_nbit-1)-1)
    return mat1, mat2, result

def matrix_to_binary_string(matrix, nbit):
    """
    将矩阵转换为二进制字符串。
    每个元素为 nbit 比特有符号整数。
    """
    binary_strings = []
    for row in matrix:
        for num in row[::-1]:
            # 将整数转换为 nbit 二进制字符串（补码表示）
            # binary_str = format(num & (2**nbit - 1), f'0{nbit}b')
            binary_str = bin(num & (2**nbit - 1))[2:].zfill(nbit)
            binary_strings.append(binary_str)
    return binary_strings

def save_to_file(filename, binary_strings, array_size, nbit):
    """
    将二进制字符串保存为符合 Verilog 格式的文本文件。
    """
    with open(filename, 'w') as f:
        for i in range(0, len(binary_strings), array_size):
            # 每行存储 array_size 个元素的二进制字符串
            line = '_'.join(binary_strings[i:i+array_size])
            f.write(f"{line}\n")

def main(args):
    # 输入参数
    array_size = args.array_size
    A_nbit, B_nbit, C_nbit = [int(x) for x in args.nbit.split(',')]
    batch_size = args.batch_size
    output_dir = args.output_dir
    # 生成矩阵
    mat1, mat2, result = generate_matrices(array_size, A_nbit, B_nbit, C_nbit, batch_size)

    # 将矩阵转换为二进制字符串
    binary_mat1 = matrix_to_binary_string(mat1.reshape(-1, array_size), A_nbit)
    binary_mat2 = matrix_to_binary_string(mat2.reshape(-1, array_size), B_nbit)

    for i in range(batch_size):
        # 保存结果
        binary_result = matrix_to_binary_string(result[i], C_nbit)
        save_to_file(os.path.join(output_dir, f'golden{i+1}.txt'), binary_result, array_size, C_nbit)

    # 保存为 Verilog 格式的文本文件
    save_to_file(os.path.join(output_dir, 'mat1.txt'), binary_mat1, array_size, A_nbit)
    save_to_file(os.path.join(output_dir, 'mat2.txt'), binary_mat2, array_size, B_nbit)

    print("矩阵已保存为 mat1.txt 和 mat2.txt")

if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument('--array_size', type=int, default=8, help='矩阵大小')
    parser.add_argument('--nbit', type=str, default="8,8,16", help='整数位数')
    parser.add_argument('--batch_size', type=int, default=3, help='批量大小')
    parser.add_argument('--output_dir', type=str, default='./bm/bm2', help='输出目录')
    args = parser.parse_args()
    main(args)