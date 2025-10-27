#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import sys
import os

def load_split_table(filename):
    """加载拆分表"""
    split_dict = {}
    try:
        with open(filename, 'r', encoding='utf-8') as f:
            for line in f:
                line = line.strip()
                if line and '\t' in line:
                    char, split_info = line.split('\t', 1)
                    split_dict[char] = split_info.strip()
        print(f"加载拆分表: {len(split_dict)} 条记录")
    except Exception as e:
        print(f"加载拆分表错误: {e}")
    return split_dict

def load_pinyin_table(filename):
    """加载拼音表，处理多个拼音的情况"""
    pinyin_dict = {}
    try:
        with open(filename, 'r', encoding='utf-8') as f:
            for line in f:
                line = line.strip()
                if line and '\t' in line:
                    char, pinyin = line.split('\t', 1)
                    pinyin = pinyin.strip()
                    
                    # 如果汉字已存在，合并拼音（用下划线连接）
                    if char in pinyin_dict:
                        existing_pinyin = pinyin_dict[char]
                        if pinyin not in existing_pinyin.split('_'):
                            pinyin_dict[char] = existing_pinyin + '_' + pinyin
                    else:
                        pinyin_dict[char] = pinyin
        print(f"加载拼音表: {len(pinyin_dict)} 条记录")
    except Exception as e:
        print(f"加载拼音表错误: {e}")
    return pinyin_dict

def load_unicode_table(filename):
    """加载Unicode表"""
    unicode_dict = {}
    try:
        with open(filename, 'r', encoding='utf-8') as f:
            for line in f:
                line = line.strip()
                if line and '\t' in line:
                    unicode_range, alias = line.split('\t', 1)
                    unicode_dict[unicode_range] = alias.strip()
        print(f"加载Unicode表: {len(unicode_dict)} 条记录")
    except Exception as e:
        print(f"加载Unicode表错误: {e}")
    return unicode_dict

def get_unicode_info(char, unicode_dict):
    """获取Unicode编码和别名"""
    # 获取Unicode编码
    unicode_code = f"U+{ord(char):04X}"
    
    # 查找对应的Unicode别名
    unicode_alias = ""
    for unicode_range, alias in unicode_dict.items():
        if '..' in unicode_range:
            start_hex, end_hex = unicode_range.split('..')
            start_code = int(start_hex[2:], 16)
            end_code = int(end_hex[2:], 16)
            char_code = ord(char)
            if start_code <= char_code <= end_code:
                unicode_alias = alias
                break
    
    return unicode_code, unicode_alias

def process_ll_div(input_file, output_file, split_dict, pinyin_dict, unicode_dict):
    """处理ll_div.txt文件并按Unicode编码排序"""
    processed_count = 0
    error_count = 0
    data_lines = []
    
    try:
        with open(input_file, 'r', encoding='utf-8') as infile:
            
            for line_num, line in enumerate(infile, 1):
                line = line.strip()
                
                # 跳过空行和注释行
                if not line or line.startswith('#'):
                    data_lines.append((0, line))  # 注释行放在最前面
                    continue
                
                # 解析每行数据
                if '\t' in line:
                    char, rest = line.split('\t', 1)
                    
                    # 获取拆分信息
                    split_info = split_dict.get(char, "")
                    
                    # 获取拼音信息
                    pinyin_info = pinyin_dict.get(char, "")
                    # 将拼音格式化为下划线连接
                    if pinyin_info:
                        pinyin_info = pinyin_info.replace(' ', '_')
                    
                    # 获取Unicode信息
                    unicode_code, unicode_alias = get_unicode_info(char, unicode_dict)
                    
                    # 构建输出行
                    output_line = f"{char}\t[{split_info},{pinyin_info},{unicode_alias},{unicode_code}]"
                    
                    # 计算Unicode编码值用于排序
                    unicode_value = ord(char)
                    data_lines.append((unicode_value, output_line))
                    
                    processed_count += 1
                    
                    # 进度显示
                    if processed_count % 1000 == 0:
                        print(f"已处理 {processed_count} 行...")
                
                else:
                    print(f"第 {line_num} 行格式错误: {line}")
                    error_count += 1
        
        # 按Unicode编码值排序
        print("正在按Unicode编码排序...")
        # 注释行保持在前，其他按Unicode值排序
        sorted_lines = []
        comment_lines = []
        data_to_sort = []
        
        for unicode_value, line in data_lines:
            if unicode_value == 0:  # 注释行
                comment_lines.append(line)
            else:
                data_to_sort.append((unicode_value, line))
        
        # 对数据行按Unicode值排序
        data_to_sort.sort(key=lambda x: x[0])
        
        # 合并结果：注释行 + 排序后的数据行
        sorted_lines = comment_lines + [line for _, line in data_to_sort]
        
        # 写入输出文件
        with open(output_file, 'w', encoding='utf-8') as outfile:
            for line in sorted_lines:
                outfile.write(line + '\n')
        
        print(f"处理完成! 共处理 {processed_count} 行，错误 {error_count} 行")
        
    except Exception as e:
        print(f"处理文件时出错: {e}")

def main():
    # 文件路径
    ll_div_file = "ll_div.txt"
    split_file = "拆分表.txt"
    pinyin_file = "拼音.txt"
    unicode_file = "Unicode.txt"
    output_file = "ll_div_full.txt"
    
    print("开始处理汉字数据...")
    
    # 加载数据表
    split_dict = load_split_table(split_file)
    pinyin_dict = load_pinyin_table(pinyin_file)
    unicode_dict = load_unicode_table(unicode_file)
    
    # 处理ll_div.txt文件
    process_ll_div(ll_div_file, output_file, split_dict, pinyin_dict, unicode_dict)
    
    print(f"处理完成! 输出文件: {output_file}")

if __name__ == "__main__":
    main()