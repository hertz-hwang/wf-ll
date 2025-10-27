package tools

import (
	"bufio"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"sort"
	"strconv"
	"strings"
	"sync"

	"gen_ll/types"
)

const fallBackFreq = 100


// BuildFullCodeMetaList 构造字符四码全码编码列表
func BuildFullCodeMetaList(table map[string][]*types.Division, mappings map[string]string, freqSet map[string]int64) (charMetaList []*types.CharMeta) {
	// 预分配足够大的切片
	charMetaList = make([]*types.CharMeta, 0, len(table))
	
	// 并发处理以提高性能
	var mutex sync.Mutex
	var wg sync.WaitGroup
	
	// 将字符表分块并行处理
	chars := make([]string, 0, len(table))
	for char := range table {
		chars = append(chars, char)
	}
	
	// 决定并发数量，根据CPU核心数自动调整
	concurrency := runtime.NumCPU()
	batchSize := (len(chars) + concurrency - 1) / concurrency
	
	for i := 0; i < concurrency; i++ {
		start := i * batchSize
		end := (i + 1) * batchSize
		if end > len(chars) {
			end = len(chars)
		}
		
		if start >= end {
			continue
		}
		
		wg.Add(1)
		go func(start, end int) {
			defer wg.Done()
			localCharMetaList := make([]*types.CharMeta, 0, end-start)
			
			// 处理当前批次的字符
			for i := start; i < end; i++ {
				char := chars[i]
				divs := table[char]
				
				// 遍历字符的所有拆分表
				for i, div := range divs {
					full, code := calcFullCodeByDiv(div.Divs, mappings)
					charMeta := types.CharMeta{
						Char:     char,
						Full:     full,
						Code:     code,
						Freq:     freqSet[char],
						MDiv:     i == 0,
						Division: div, // 绑定对应的拆分信息
					}
					
					localCharMetaList = append(localCharMetaList, &charMeta)
				}
			}
			
			// 合并本地结果到全局列表
			mutex.Lock()
			charMetaList = append(charMetaList, localCharMetaList...)
			mutex.Unlock()
		}(start, end)
	}
	
	// 等待所有协程完成
	wg.Wait()
	
	// 排序结果 - 按词频降序排序
	sortCharMetaByFreq(charMetaList)
	return
}


func sortCharMetaByCode(charMetaList []*types.CharMeta) {
	// 按编码升序排列，对于相同编码的重码按词频降序排列
	sort.Slice(charMetaList, func(i, j int) bool {
		a, b := charMetaList[i], charMetaList[j]
		
		// 首先按编码升序排列
		if a.Code != b.Code {
			return a.Code < b.Code
		}
		
		// 编码相同，按词频降序排列
		if a.Freq != b.Freq {
			return a.Freq > b.Freq
		}
		
		// 编码和词频都相同，按字符Unicode编码升序排列
		return a.Char < b.Char
	})
}

func sortCharMetaByFreq(charMetaList []*types.CharMeta) {
	// 按词频降序排列，词频相同时按编码升序排列
	sort.Slice(charMetaList, func(i, j int) bool {
		a, b := charMetaList[i], charMetaList[j]
		
		// 首先按词频降序排列
		if a.Freq != b.Freq {
			return a.Freq > b.Freq
		}
		
		// 词频相同，按编码升序排列
		if a.Code != b.Code {
			return a.Code < b.Code
		}
		
		// 词频和编码都相同，按字符Unicode编码升序排列
		return a.Char < b.Char
	})
}


func calcFullCodeByDiv(div []string, mappings map[string]string) (full string, code string) {
	// 遍历处理每个部件，生成全码
	for i, comp := range div {
		compCode := mappings[comp]
		if len(compCode) == 0 {
			continue
		}
		// 在各部件编码之间添加"_"分隔符
		if i > 0 {
			full += "_"
		}
		full += compCode
	}
	
	// 根据拆分部件数量生成编码
	if len(div) == 1 {
		// 单根字处理
		compCode := mappings[div[0]]
		if len(compCode) == 0 {
			return "", ""
		}
		
		// 第一码：取部件大码（编码第一位）
		code = compCode[:1]
		
		// 第二码：取部件中码
		if len(compCode) >= 2 {
			code += compCode[1:2]
		} else {
			// 如果只有1码，重复大码
			code += compCode[:1]
		}
		
		// 第三码：取部件中码（重复第二码）
		if len(compCode) >= 2 {
			code += compCode[1:2]
		} else {
			// 如果只有1码，重复大码
			code += compCode[:1]
		}
		
		// 第四码：取部件小码
		if len(compCode) >= 3 {
			code += compCode[2:3]
		} else if len(compCode) == 2 {
			// 如果只有双编码，取中码
			code += compCode[1:2]
		} else {
			// 如果只有1码，重复大码
			code += compCode[:1]
		}
		
	} else if len(div) == 2 {
		// 双根字处理
		firstCompCode := mappings[div[0]]
		secondCompCode := mappings[div[1]]
		
		if len(firstCompCode) == 0 || len(secondCompCode) == 0 {
			return "", ""
		}
		
		// 第一码：第一部件大码
		code = firstCompCode[:1]
		
		// 第二码：第二部件大码
		code += secondCompCode[:1]
		
		// 第三码：第二部件中码
		if len(secondCompCode) >= 2 {
			code += secondCompCode[1:2]
		} else {
			// 如果只有1码，重复大码
			code += secondCompCode[:1]
		}
		
		// 第四码：第二部件小码
		if len(secondCompCode) >= 3 {
			code += secondCompCode[2:3]
		} else if len(secondCompCode) == 2 {
			// 如果只有双编码，取中码
			code += secondCompCode[1:2]
		} else {
			// 如果只有1码，重复大码
			code += secondCompCode[:1]
		}
		
	} else {
		// 三根字及以上多根字处理
		firstCompCode := mappings[div[0]]
		secondCompCode := mappings[div[1]]
		lastCompCode := mappings[div[len(div)-1]]
		
		if len(firstCompCode) == 0 || len(secondCompCode) == 0 || len(lastCompCode) == 0 {
			return "", ""
		}
		
		// 第一码：第一部件大码
		code = firstCompCode[:1]
		
		// 第二码：第二部件大码
		code += secondCompCode[:1]
		
		// 第三码：末部件大码
		code += lastCompCode[:1]
		
		// 第四码：末部件小码
		if len(lastCompCode) >= 3 {
			code += lastCompCode[2:3]
		} else if len(lastCompCode) == 2 {
			// 如果只有双编码，取中码
			code += lastCompCode[1:2]
		} else {
			// 如果只有1码，重复大码
			code += lastCompCode[:1]
		}
	}
	
	// 确保编码长度不超过4码
	if len(code) > 4 {
		code = code[:4]
	}
	
	code = strings.ToLower(code)
	return
}

// ParseLenCodeLimit 解析简码长度限制字符串
func ParseLenCodeLimit(limitStr string) (map[int]int, error) {
	limits := make(map[int]int)
	if limitStr == "" {
		return limits, nil
	}
	
	pairs := strings.Split(limitStr, ",")
	for _, pair := range pairs {
		parts := strings.Split(pair, ":")
		if len(parts) != 2 {
			continue
		}
		
		length, err := strconv.Atoi(strings.TrimSpace(parts[0]))
		if err != nil {
			return nil, err
		}
		
		limit, err := strconv.Atoi(strings.TrimSpace(parts[1]))
		if err != nil {
			return nil, err
		}
		
		limits[length] = limit
	}
	
	return limits, nil
}

// BuildSimpleCodeList 构建简码列表
func BuildSimpleCodeList(fullCodeList []*types.CharMeta, lenCodeLimit map[int]int, noSimplifyChars []string) []*types.CharMeta {
	// 按词频排序
	sortedList := make([]*types.CharMeta, len(fullCodeList))
	copy(sortedList, fullCodeList)
	sort.Slice(sortedList, func(i, j int) bool {
		return sortedList[i].Freq > sortedList[j].Freq
	})
	
	// 出简不出全 - 只保留成功简化的条目
	resultData := make([]*types.CharMeta, 0)
	usedCodes := make(map[string]bool)
	
	// 创建不出简字符的集合
	noSimplifySet := make(map[string]bool)
	for _, char := range noSimplifyChars {
		noSimplifySet[char] = true
	}
	
	for _, charMeta := range sortedList {
		word := charMeta.Char
		code := charMeta.Code
		freq := charMeta.Freq
		
		// 跳过不出简的字符
		if noSimplifySet[word] {
			continue
		}
		
		fullCodeLastChar := string(code[len(code)-1])
		var simplified string
		
		// 尝试生成简码
		for i := 0; i < len(code); i++ {
			limit := lenCodeLimit[i+1]
			if limit == 0 {
				continue
			}
			
			currentPrefix := code[:i+1]
			// 计算目标简码长度：1简和2简是前缀长度+1（因为加末码），3简及以上是前缀长度
			var targetLength int
			if i+1 <= 2 {
				targetLength = (i + 1) + 1
			} else {
				targetLength = i + 1
			}
			
			// 统计相同前缀的简码数量
			samePrefixCount := 0
			for _, res := range resultData {
				resCode := res.Code
				if len(resCode) == targetLength && strings.HasPrefix(resCode, currentPrefix) {
					samePrefixCount++
				}
			}
			
			if samePrefixCount >= limit {
				continue
			}
			
			// 生成候选简码
			var candidate string
			if i+1 <= 2 {
				candidate = currentPrefix + fullCodeLastChar
			} else {
				candidate = currentPrefix
			}
			
			if !usedCodes[candidate] {
				simplified = candidate
				usedCodes[simplified] = true
				break
			}
		}
		
		// 如果生成了简码且与全码不同，则添加到结果
		if simplified != "" && simplified != code {
			newCharMeta := &types.CharMeta{
				Char: word,
				Code: simplified,
				Freq: freq,
				Simp: true,
			}
			resultData = append(resultData, newCharMeta)
		}
	}
	
	// 按词频排序结果
	sortCharMetaByFreq(resultData)
	return resultData
}


// BuildWordsFullCode 构建多字词全码
func BuildWordsFullCode(wordEntries []*types.WordEntry, charCodeMap map[string]string) []*types.WordCode {
	wordCodes := make([]*types.WordCode, 0, len(wordEntries))
	
	for _, entry := range wordEntries {
		word := entry.Word
		chars := []rune(word)
		
		// 先去除所有标点符号，只保留可编码的汉字字符
		var validChars []rune
		for _, char := range chars {
			charStr := string(char)
			if code := charCodeMap[charStr]; code != "" && len(code) >= 1 {
				validChars = append(validChars, char)
			}
		}
		
		// 根据去除标点后的有效字符数量应用编码规则
		var code string
		switch len(validChars) {
		case 2:
			// 二字词：取每个字编码的前2位，拼接成4位编码
			firstCode := charCodeMap[string(validChars[0])]
			secondCode := charCodeMap[string(validChars[1])]
			
			if len(firstCode) >= 2 && len(secondCode) >= 2 {
				code = firstCode[:2] + secondCode[:2]
			}
			
		case 3:
			// 三字词：前两个字各取编码的第1位，第三个字取编码的前2位
			firstCode := charCodeMap[string(validChars[0])]
			secondCode := charCodeMap[string(validChars[1])]
			thirdCode := charCodeMap[string(validChars[2])]
			
			if len(firstCode) >= 1 && len(secondCode) >= 1 && len(thirdCode) >= 2 {
				code = firstCode[:1] + secondCode[:1] + thirdCode[:2]
			}
			
		default:
			// 四字及以上：取第一、二、三个字和最后一个字编码的第1位
			if len(validChars) >= 4 {
				firstCode := charCodeMap[string(validChars[0])]
				secondCode := charCodeMap[string(validChars[1])]
				thirdCode := charCodeMap[string(validChars[2])]
				lastCode := charCodeMap[string(validChars[len(validChars)-1])]
				
				if len(firstCode) >= 1 && len(secondCode) >= 1 && len(thirdCode) >= 1 && len(lastCode) >= 1 {
					code = firstCode[:1] + secondCode[:1] + thirdCode[:1] + lastCode[:1]
				}
			}
		}
		
		// 如果成功生成了编码，添加到结果列表
		if code != "" {
			wordCodes = append(wordCodes, &types.WordCode{
				Word:   word,
				Code:   code,
				Weight: entry.Weight,
			})
		}
	}
	
	return wordCodes
}

// CreateCharCodeMap 从字符元数据列表创建字符到编码的映射
func CreateCharCodeMap(charMetaList []*types.CharMeta) map[string]string {
	charCodeMap := make(map[string]string)
	
	for _, charMeta := range charMetaList {
		// 只使用主要拆分的编码
		if charMeta.MDiv {
			charCodeMap[charMeta.Char] = charMeta.Code
		}
	}
	
	return charCodeMap
}

// SortWordCodes 对多字词编码进行排序
// 排序规则：先按权重降序排列，权重相同时按编码升序排列
func SortWordCodes(wordCodes []*types.WordCode) {
	sort.Slice(wordCodes, func(i, j int) bool {
		a, b := wordCodes[i], wordCodes[j]
		
		// 首先按权重降序排列
		weightA := parseWeight(a.Weight)
		weightB := parseWeight(b.Weight)
		
		if weightA != weightB {
			return weightA > weightB
		}
		
		// 权重相同，按编码升序排列
		if a.Code != b.Code {
			return a.Code < b.Code
		}
		
		// 权重和编码都相同，按词语Unicode编码升序排列（保持稳定排序）
		return a.Word < b.Word
	})
}

// parseWeight 解析权重字符串为数值
// 如果权重为空或解析失败，返回默认值0
func parseWeight(weightStr string) int64 {
	if weightStr == "" {
		return 0
	}
	
	// 尝试解析为整数
	weight, err := strconv.ParseInt(weightStr, 10, 64)
	if err != nil {
		return 0
	}
	
	return weight
}

// BuildWordsSimpleCode 构建多字词简码
func BuildWordsSimpleCode(wordCodes []*types.WordCode, lenCodeLimit map[int]int) []*types.WordSimpleCode {
	// 按权重降序排序（权重高的优先分配简码）
	sortedWordCodes := make([]*types.WordCode, len(wordCodes))
	copy(sortedWordCodes, wordCodes)
	sort.Slice(sortedWordCodes, func(i, j int) bool {
		weightA := parseWeight(sortedWordCodes[i].Weight)
		weightB := parseWeight(sortedWordCodes[j].Weight)
		return weightA > weightB
	})

	// 初始化每个简码长度的计数器
	codeCounters := make(map[int]map[string]int)
	for length := 1; length <= 3; length++ {
		codeCounters[length] = make(map[string]int)
	}

	// 处理每个词
	resultData := make([]*types.WordSimpleCode, 0)
	for _, wordCode := range sortedWordCodes {
		word := wordCode.Word
		code := wordCode.Code
		weight := wordCode.Weight
		wordLength := len([]rune(word)) // 获取词的长度

		// 按照顺序尝试分配简码：先一简，再二简，最后三简
		var simplifiedCode string
		for codeLength := 1; codeLength <= 3; codeLength++ {
			// 检查该长度是否允许
			limit := lenCodeLimit[codeLength]
			if limit == 0 {
				continue
			}

			// 检查该长度的简码是否适用于当前词
			if codeLength == 2 && wordLength != 2 { // 二简只适用于二字词
				continue
			}
			if codeLength == 3 && wordLength != 3 { // 三简只适用于三字词
				continue
			}

			// 获取基础简码
			var baseCode string
			if codeLength == 2 && wordLength == 2 {
				// 二字词特殊规则：首码 + 第三个码
				if len(code) >= 3 {
					baseCode = code[:1] + code[2:3]
				} else {
					continue // 编码长度不足，跳过
				}
			} else {
				// 普通规则：取编码前codeLength位
				if len(code) >= codeLength {
					baseCode = code[:codeLength]
				} else {
					continue // 编码长度不足，跳过
				}
			}

			// 检查是否已达到该基础简码的限制
			currentCount := codeCounters[codeLength][baseCode]
			if currentCount < limit {
				// 创建新的简码条目
				simplifiedCode = baseCode

				resultData = append(resultData, &types.WordSimpleCode{
					Word:   word,
					Code:   simplifiedCode,
					Weight: weight,
				})
				codeCounters[codeLength][baseCode] = currentCount + 1
				break // 找到可用的简码后就不再尝试更长的简码
			}
		}
	}

	// 先排序
	SortWordSimpleCodes(resultData)

	// 然后在排序后的结果中添加占位符
	resultData = addPlaceholdersAfterSort(resultData, lenCodeLimit)

	return resultData
}

// BuildLinglongSimpleCode 构建玲珑多字词简码（不添加占位符）
func BuildLinglongSimpleCode(wordCodes []*types.WordCode, lenCodeLimit map[int]int) []*types.WordSimpleCode {
	// 按权重降序排序（权重高的优先分配简码）
	sortedWordCodes := make([]*types.WordCode, len(wordCodes))
	copy(sortedWordCodes, wordCodes)
	sort.Slice(sortedWordCodes, func(i, j int) bool {
		weightA := parseWeight(sortedWordCodes[i].Weight)
		weightB := parseWeight(sortedWordCodes[j].Weight)
		return weightA > weightB
	})

	// 初始化每个简码长度的计数器
	codeCounters := make(map[int]map[string]int)
	for length := 1; length <= 3; length++ {
		codeCounters[length] = make(map[string]int)
	}

	// 处理每个词
	resultData := make([]*types.WordSimpleCode, 0)
	for _, wordCode := range sortedWordCodes {
		word := wordCode.Word
		code := wordCode.Code
		weight := wordCode.Weight
		wordLength := len([]rune(word)) // 获取词的长度

		// 按照顺序尝试分配简码：先一简，再二简，最后三简
		var simplifiedCode string
		for codeLength := 1; codeLength <= 3; codeLength++ {
			// 检查该长度是否允许
			limit := lenCodeLimit[codeLength]
			if limit == 0 {
				continue
			}

			// 检查该长度的简码是否适用于当前词
			if codeLength == 2 && wordLength != 2 { // 二简只适用于二字词
				continue
			}
			if codeLength == 3 && wordLength != 3 { // 三简只适用于三字词
				continue
			}

			// 获取基础简码
			var baseCode string
			if codeLength == 2 && wordLength == 2 {
				// 二字词特殊规则：首码 + 第三个码
				if len(code) >= 3 {
					baseCode = code[:1] + code[2:3]
				} else {
					continue // 编码长度不足，跳过
				}
			} else {
				// 普通规则：取编码前codeLength位
				if len(code) >= codeLength {
					baseCode = code[:codeLength]
				} else {
					continue // 编码长度不足，跳过
				}
			}

			// 检查是否已达到该基础简码的限制
			currentCount := codeCounters[codeLength][baseCode]
			if currentCount < limit {
				// 创建新的简码条目
				simplifiedCode = baseCode

				resultData = append(resultData, &types.WordSimpleCode{
					Word:   word,
					Code:   simplifiedCode,
					Weight: weight,
				})
				codeCounters[codeLength][baseCode] = currentCount + 1
				break // 找到可用的简码后就不再尝试更长的简码
			}
		}
	}

	// 只排序，不添加占位符
	SortWordSimpleCodes(resultData)

	return resultData
}

// addPlaceholdersAfterSort 在排序后为多字词简码添加占位符
func addPlaceholdersAfterSort(wordSimpleCodes []*types.WordSimpleCode, lenCodeLimit map[int]int) []*types.WordSimpleCode {
	result := make([]*types.WordSimpleCode, 0, len(wordSimpleCodes))

	// 按编码分组处理
	currentGroup := make([]*types.WordSimpleCode, 0)
	var currentCode string

	for _, item := range wordSimpleCodes {
		if item.Code != currentCode {
			// 处理前一个组
			if len(currentGroup) > 0 {
				result = append(result, currentGroup...)
				// 为前一个组添加占位符
				result = appendGroupPlaceholders(result, currentGroup, lenCodeLimit)
			}
			// 开始新组
			currentGroup = []*types.WordSimpleCode{item}
			currentCode = item.Code
		} else {
			// 添加到当前组
			currentGroup = append(currentGroup, item)
		}
	}

	// 处理最后一个组
	if len(currentGroup) > 0 {
		result = append(result, currentGroup...)
		// 为最后一个组添加占位符
		result = appendGroupPlaceholders(result, currentGroup, lenCodeLimit)
	}

	// 为所有可能的基础编码添加占位符（包括空码位）
	result = addAllPossiblePlaceholders(result, lenCodeLimit)

	return result
}

// appendGroupPlaceholders 为单个编码组添加占位符
func appendGroupPlaceholders(result []*types.WordSimpleCode, group []*types.WordSimpleCode, lenCodeLimit map[int]int) []*types.WordSimpleCode {
	if len(group) == 0 {
		return result
	}

	// 获取编码长度
	codeLength := len(group[0].Code)
	limit := lenCodeLimit[codeLength]
	if limit == 0 {
		return result
	}

	// 如果当前组数量小于限制，添加占位符
	if len(group) < limit {
		startIndex := len(group) + 1
		count := limit - len(group)
		placeholders := generatePlaceholders(startIndex, count, limit)
		for _, placeholder := range placeholders {
			// 使用硬编码的占位符权重
			weight := getPlaceholderWeight(placeholder)
			result = append(result, &types.WordSimpleCode{
				Word:   placeholder,
				Code:   group[0].Code,
				Weight: weight,
			})
		}
	}

	return result
}

// addAllPossiblePlaceholders 为所有可能的基础编码添加占位符（包括空码位）
func addAllPossiblePlaceholders(wordSimpleCodes []*types.WordSimpleCode, lenCodeLimit map[int]int) []*types.WordSimpleCode {
	result := make([]*types.WordSimpleCode, len(wordSimpleCodes))
	copy(result, wordSimpleCodes)

	// 为每个简码长度和基础简码添加占位符
	for codeLength := 1; codeLength <= 3; codeLength++ {
		limit := lenCodeLimit[codeLength]
		if limit == 0 {
			continue
		}

		// 获取该长度所有可能的基础简码
		allBaseCodes := generateAllBaseCodes(codeLength)
		
		for _, baseCode := range allBaseCodes {
			// 检查该基础编码是否已经有实际词
			hasActualWord := false
			for _, item := range wordSimpleCodes {
				if item.Code == baseCode && !isPlaceholder(item.Word) {
					hasActualWord = true
					break
				}
			}
			
			// 如果没有实际词，需要添加完整的占位符
			if !hasActualWord {
				placeholders := generatePlaceholders(1, limit, limit)
				for _, placeholder := range placeholders {
					// 使用硬编码的占位符权重
					weight := getPlaceholderWeight(placeholder)
					result = append(result, &types.WordSimpleCode{
						Word:   placeholder,
						Code:   baseCode,
						Weight: weight,
					})
				}
			}
		}
	}

	return result
}

// addPlaceholders 为多字词简码添加占位符
func addPlaceholders(wordSimpleCodes []*types.WordSimpleCode, codeCounters map[int]map[string]int, lenCodeLimit map[int]int) []*types.WordSimpleCode {
	result := make([]*types.WordSimpleCode, len(wordSimpleCodes))
	copy(result, wordSimpleCodes)

	// 为每个简码长度和基础简码添加占位符
	for codeLength := 1; codeLength <= 3; codeLength++ {
		limit := lenCodeLimit[codeLength]
		if limit == 0 {
			continue
		}

		// 获取该长度所有可能的基础简码
		allBaseCodes := generateAllBaseCodes(codeLength)
		
		for _, baseCode := range allBaseCodes {
			currentCount := codeCounters[codeLength][baseCode]
			
			// 如果当前数量小于限制，需要添加占位符
			if currentCount < limit {
				// 占位符从当前数量+1开始编号
				startIndex := currentCount + 1
				count := limit - currentCount
				placeholders := generatePlaceholders(startIndex, count, limit)
				for _, placeholder := range placeholders {
					result = append(result, &types.WordSimpleCode{
						Word:   placeholder,
						Code:   baseCode,
						Weight: "0", // 占位符权重设为0
					})
				}
			}
		}
	}

	return result
}

// generateAllBaseCodes 生成所有可能的基础简码组合
func generateAllBaseCodes(codeLength int) []string {
	// 24个键：qtypasdfghjkl;zxcvbnm,./
	keys := []string{"q", "t", "y", "p", "a", "s", "d", "f", "g", "h", "j", "k", "l", ";", "z", "x", "c", "v", "b", "n", "m", ",", ".", "/"}
	
	if codeLength == 1 {
		return keys
	}
	
	// 生成所有可能的组合
	var result []string
	switch codeLength {
	case 2:
		for _, first := range keys {
			for _, second := range keys {
				result = append(result, first+second)
			}
		}
	case 3:
		for _, first := range keys {
			for _, second := range keys {
				for _, third := range keys {
					result = append(result, first+second+third)
				}
			}
		}
	default:
		return nil
	}
	
	return result
}

// SortWordSimpleCodes 对多字词简码进行排序
// 排序规则：先按编码升序排列，编码相同时按权重降序排列，占位符排在正常词后面
func SortWordSimpleCodes(wordSimpleCodes []*types.WordSimpleCode) {
	sort.Slice(wordSimpleCodes, func(i, j int) bool {
		a, b := wordSimpleCodes[i], wordSimpleCodes[j]

		// 首先按编码升序排列
		if a.Code != b.Code {
			return a.Code < b.Code
		}

		// 编码相同，检查是否为占位符
		aIsPlaceholder := isPlaceholder(a.Word)
		bIsPlaceholder := isPlaceholder(b.Word)
		
		// 占位符排在正常词后面
		if aIsPlaceholder != bIsPlaceholder {
			return !aIsPlaceholder // 如果a不是占位符而b是占位符，a排在前面
		}

		// 如果都是占位符，按占位符编号升序排列
		if aIsPlaceholder && bIsPlaceholder {
			return getPlaceholderIndex(a.Word) < getPlaceholderIndex(b.Word)
		}

		// 都是正常词，按权重降序排列
		weightA := parseWeight(a.Weight)
		weightB := parseWeight(b.Weight)

		if weightA != weightB {
			return weightA > weightB
		}

		// 编码和权重都相同，按词语Unicode编码升序排列（保持稳定排序）
		return a.Word < b.Word
	})
}

// isPlaceholder 检查是否为占位符
func isPlaceholder(word string) bool {
	// 占位符是①、②、③、④等字符
	if len(word) == 1 {
		r := rune(word[0])
		return r >= '①' && r <= '⑩'
	}
	return false
}

// getPlaceholderIndex 获取占位符的编号（①=1, ②=2, ...）
func getPlaceholderIndex(word string) int {
	if !isPlaceholder(word) {
		return 0
	}
	r := rune(word[0])
	return int(r - '①' + 1)
}

// getPlaceholderWeight 获取占位符的硬编码权重
func getPlaceholderWeight(word string) string {
	// 硬编码占位符权重映射表
	weightMap := map[string]string{
		"①": "-1",
		"②": "-2",
		"③": "-3",
		"④": "-4",
		"⑤": "-5",
		"⑥": "-6",
		"⑦": "-7",
		"⑧": "-8",
		"⑨": "-9",
		"⑩": "-10",
	}
	
	if weight, exists := weightMap[word]; exists {
		return weight
	}
	
	// 对于未知占位符，返回默认值
	return "-0"
}

// DictEntry 表示字典条目
type DictEntry struct {
	Text string
	Code string
	Freq int64
}

// AppendToDictFile 将源文件内容追加到目标字典文件
// sourceFile: 源文件路径
// targetFile: 目标字典文件路径
// needSort: 是否需要排序（编码升序，重码组内按词频降序）
// removeFreq: 是否需要删除词频列
func AppendToDictFile(sourceFile, targetFile string, needSort, removeFreq bool) error {
	var sourceContent string
	var err error
	
	if needSort {
		// 如果需要排序，使用readSourceFile读取完整的DictEntry列表
		entries, err := readSourceFile(sourceFile, !removeFreq) // 保留词频用于排序
		if err != nil {
			return fmt.Errorf("读取源文件失败: %w", err)
		}
		
		// 排序
		sortDictEntries(entries)
		
		// 对LL.chars.full.dict.yaml进行特殊处理：简码汉字下移
		if strings.Contains(targetFile, "LL.chars.full.dict.yaml") {
			entries = processSimpleCharsInFullDict(entries)
		}
		
		// 构建排序后的内容
		var result strings.Builder
		for _, entry := range entries {
			result.WriteString(fmt.Sprintf("%s\t%s\n", entry.Text, entry.Code))
		}
		sourceContent = result.String()
	} else {
		// 如果不需要排序，直接读取内容
		sourceContent, err = readSourceFileContent(sourceFile, removeFreq)
		if err != nil {
			return fmt.Errorf("读取源文件失败: %w", err)
		}
	}
	
	// 简单的追加操作：在目标文件末尾添加源文件内容
	err = appendToFile(targetFile, sourceContent)
	if err != nil {
		return fmt.Errorf("追加到目标文件失败: %w", err)
	}
	
	return nil
}

// readSourceFileContent 读取源文件内容并处理词频列
func readSourceFileContent(filepath string, removeFreq bool) (string, error) {
	file, err := os.Open(filepath)
	if err != nil {
		return "", err
	}
	defer file.Close()
	
	var content strings.Builder
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		
		fields := strings.Split(line, "\t")
		if len(fields) < 2 {
			continue
		}
		
		// 如果需要删除词频，只保留前两列
		if removeFreq && len(fields) >= 3 {
			content.WriteString(fmt.Sprintf("%s\t%s\n", fields[0], fields[1]))
		} else {
			content.WriteString(line + "\n")
		}
	}
	
	if err := scanner.Err(); err != nil {
		return "", err
	}
	
	return content.String(), nil
}

// sortSourceContent 对源文件内容进行排序
func sortSourceContent(content string) string {
	lines := strings.Split(strings.TrimSpace(content), "\n")
	
	// 解析为DictEntry列表进行排序
	var entries []*DictEntry
	for _, line := range lines {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		fields := strings.Split(line, "\t")
		if len(fields) >= 2 {
			entry := &DictEntry{
				Text: fields[0],
				Code: fields[1],
			}
			// 如果有词频信息，解析词频
			if len(fields) >= 3 {
				freq, err := strconv.ParseInt(fields[2], 10, 64)
				if err == nil {
					entry.Freq = freq
				} else {
					// 如果解析失败，设置默认词频为0
					entry.Freq = 0
				}
			} else {
				// 如果没有词频信息，设置默认词频为0
				entry.Freq = 0
			}
			entries = append(entries, entry)
		}
	}
	
	// 排序
	sortDictEntries(entries)
	
	// 重新构建内容
	var result strings.Builder
	for _, entry := range entries {
		result.WriteString(fmt.Sprintf("%s\t%s\n", entry.Text, entry.Code))
	}
	
	return result.String()
}

// appendToFile 将内容追加到文件末尾
func appendToFile(filepath, content string) error {
	file, err := os.OpenFile(filepath, os.O_APPEND|os.O_WRONLY|os.O_CREATE, 0644)
	if err != nil {
		return err
	}
	defer file.Close()
	
	_, err = file.WriteString(content)
	return err
}

// readSourceFile 读取源文件并解析为DictEntry列表
func readSourceFile(filepath string, removeFreq bool) ([]*DictEntry, error) {
	file, err := os.Open(filepath)
	if err != nil {
		return nil, err
	}
	defer file.Close()
	
	var entries []*DictEntry
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		
		fields := strings.Split(line, "\t")
		if len(fields) < 2 {
			continue
		}
		
		entry := &DictEntry{
			Text: fields[0],
			Code: fields[1],
		}
		
		// 如果有第三列且不需要删除词频，解析词频
		if len(fields) >= 3 && !removeFreq {
			freq, err := strconv.ParseInt(fields[2], 10, 64)
			if err == nil {
				entry.Freq = freq
			}
		}
		
		entries = append(entries, entry)
	}
	
	if err := scanner.Err(); err != nil {
		return nil, err
	}
	
	return entries, nil
}

// readDictFile 读取字典文件并解析为DictEntry列表
func readDictFile(filepath string) ([]*DictEntry, error) {
	file, err := os.Open(filepath)
	if err != nil {
		if os.IsNotExist(err) {
			// 文件不存在，返回空列表
			return []*DictEntry{}, nil
		}
		return nil, err
	}
	defer file.Close()
	
	var entries []*DictEntry
	scanner := bufio.NewScanner(file)
	
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		
		// 跳过注释和元数据
		if strings.HasPrefix(line, "#") || line == "---" || line == "..." {
			continue
		}
		
		// 检查是否进入数据部分
		if strings.HasPrefix(line, "name:") || strings.HasPrefix(line, "version:") ||
		   strings.HasPrefix(line, "sort:") || strings.HasPrefix(line, "columns:") ||
		   strings.HasPrefix(line, "encoder:") {
			continue
		}
		
		// 跳过空行
		if line == "" {
			continue
		}
		
		// 解析数据行
		fields := strings.Split(line, "\t")
		if len(fields) >= 2 {
			entry := &DictEntry{
				Text: fields[0],
				Code: fields[1],
			}
			entries = append(entries, entry)
		}
	}
	
	if err := scanner.Err(); err != nil {
		return nil, err
	}
	
	return entries, nil
}

// sortDictEntries 对字典条目进行排序
// 排序规则：编码升序，重码组内按词频降序（与跟打词提的排序规则保持一致）
func sortDictEntries(entries []*DictEntry) {
	// 使用sort.SliceStable进行稳定排序，确保词频相同时保持原始顺序
	sort.SliceStable(entries, func(i, j int) bool {
		a, b := entries[i], entries[j]
		
		// 首先按编码升序排列
		if a.Code != b.Code {
			return a.Code < b.Code
		}
		
		// 编码相同，按词频降序排列
		return a.Freq > b.Freq
	})
}

// processSimpleCharsInFullDict 对LL.chars.full.dict.yaml中的简码汉字进行特殊处理
func processSimpleCharsInFullDict(entries []*DictEntry) []*DictEntry {
	// 读取简码文件，构建简码汉字映射
	simpleChars := loadSimpleChars()
	
	// 按编码分组处理
	groupedEntries := groupEntriesByCode(entries)
	
	// 对每个编码组进行特殊处理，然后重新组装
	result := make([]*DictEntry, 0, len(entries))
	for _, group := range groupedEntries {
		processedGroup := processCodeGroup(group, simpleChars)
		result = append(result, processedGroup...)
	}
	
	return result
}

// loadSimpleChars 从code_chars_simp.txt加载简码汉字信息
func loadSimpleChars() map[string]int {
	simpleChars := make(map[string]int)
	
	// 简码文件路径，这里假设在deploy/tmp目录下
	simpleFile := "../deploy/tmp/code_chars_simp.txt"
	file, err := os.Open(simpleFile)
	if err != nil {
		// 如果文件不存在，返回空映射
		return simpleChars
	}
	defer file.Close()
	
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		
		fields := strings.Split(line, "\t")
		if len(fields) < 2 {
			continue
		}
		
		char := fields[0]
		code := fields[1]
		
		// 根据编码长度判断是一简还是二简
		// 一简：编码长度为1或2（一简+补码）
		// 二简：编码长度为2或3（二简+补码）
		if len(code) == 1 || len(code) == 2 {
			simpleChars[char] = 1 // 一简（包括一简+补码）
		} else if len(code) == 3 {
			simpleChars[char] = 2 // 二简（包括二简+补码）
		}
	}
	
	return simpleChars
}

// groupEntriesByCode 按编码对条目进行分组，保持原有编码顺序
func groupEntriesByCode(entries []*DictEntry) [][]*DictEntry {
	groups := make(map[string][]*DictEntry)
	codeOrder := make([]string, 0)
	
	for _, entry := range entries {
		if _, exists := groups[entry.Code]; !exists {
			codeOrder = append(codeOrder, entry.Code)
		}
		groups[entry.Code] = append(groups[entry.Code], entry)
	}
	
	// 按原有编码顺序转换为切片
	result := make([][]*DictEntry, 0, len(groups))
	for _, code := range codeOrder {
		result = append(result, groups[code])
	}
	
	return result
}

// processCodeGroup 处理单个编码组的简码汉字特殊排序
func processCodeGroup(group []*DictEntry, simpleChars map[string]int) []*DictEntry {
	if len(group) < 3 {
		// 如果重码组内候选不足三个，不应用特殊规则
		return group
	}
	
	// 创建副本进行处理，避免影响原始数据
	result := make([]*DictEntry, len(group))
	copy(result, group)
	
	// 第一步：处理一简汉字，下移2行
	result = moveSimpleChars(result, simpleChars, 1, 2)
	
	// 第二步：处理二简汉字，下移2行
	result = moveSimpleChars(result, simpleChars, 2, 2)
	
	// 第三步：处理"的"、"了"二字，下移2位
	result = moveSpecialChars(result)
	
	return result
}

// moveSimpleChars 移动简码汉字
func moveSimpleChars(group []*DictEntry, simpleChars map[string]int, simpleType int, moveCount int) []*DictEntry {
	result := make([]*DictEntry, len(group))
	copy(result, group)
	
	// 找到所有指定类型的简码汉字
	simpleIndices := make([]int, 0)
	for i, entry := range result {
		if simpleChars[entry.Text] == simpleType {
			simpleIndices = append(simpleIndices, i)
		}
	}
	
	// 对每个简码汉字进行移动（从后往前处理，避免索引变化）
	for i := len(simpleIndices) - 1; i >= 0; i-- {
		idx := simpleIndices[i]
		if idx+moveCount < len(result) {
			// 将简码汉字下移moveCount个位置
			temp := result[idx]
			for j := idx; j < idx+moveCount; j++ {
				result[j] = result[j+1]
			}
			result[idx+moveCount] = temp
		}
	}
	
	return result
}

// moveSpecialChars 移动特殊字符"的"和"了"
func moveSpecialChars(group []*DictEntry) []*DictEntry {
	result := make([]*DictEntry, len(group))
	copy(result, group)
	
	specialChars := map[string]bool{
		"的": true,
		"了": true,
	}
	
	// 找到特殊字符的位置
	for i, entry := range result {
		if specialChars[entry.Text] {
			// 下移2位
			if i+2 < len(result) {
				temp := result[i]
				for j := i; j < i+2; j++ {
					result[j] = result[j+1]
				}
				result[i+2] = temp
			}
			break // 每次只处理一个特殊字符
		}
	}
	
	return result
}

// mergeDictEntries 合并字典条目，避免重复
func mergeDictEntries(existing, new []*DictEntry) []*DictEntry {
	// 创建现有条目的映射
	existingMap := make(map[string]string)
	for _, entry := range existing {
		existingMap[entry.Text] = entry.Code
	}
	
	// 创建结果列表，先包含现有条目
	result := make([]*DictEntry, len(existing))
	copy(result, existing)
	
	// 添加新条目，避免重复
	for _, entry := range new {
		if _, exists := existingMap[entry.Text]; !exists {
			result = append(result, entry)
		}
	}
	
	return result
}

// writeDictFile 将字典条目写入文件
func writeDictFile(filepath string, entries []*DictEntry) error {
	// 读取原始文件的完整内容
	originalContent, err := readDictFileContent(filepath)
	if err != nil && !os.IsNotExist(err) {
		return err
	}
	
	file, err := os.Create(filepath)
	if err != nil {
		return err
	}
	defer file.Close()
	
	writer := bufio.NewWriter(file)
	
	// 写入原始头部信息
	if originalContent != "" {
		// 找到数据部分的开始位置
		dataStart := findDataSectionStart(originalContent)
		if dataStart > 0 {
			// 写入头部信息
			writer.WriteString(originalContent[:dataStart])
		} else {
			// 如果没有找到数据部分，写入默认头部
			writer.WriteString(getDefaultHeader(filepath))
		}
	} else {
		// 文件不存在，写入默认头部
		writer.WriteString(getDefaultHeader(filepath))
	}
	
	// 写入数据条目
	for _, entry := range entries {
		line := fmt.Sprintf("%s\t%s\n", entry.Text, entry.Code)
		if _, err := writer.WriteString(line); err != nil {
			return err
		}
	}
	
	// 写入尾部信息
	writer.WriteString("...\n")
	
	return writer.Flush()
}

// readDictFileContent 读取字典文件的完整内容
func readDictFileContent(filepath string) (string, error) {
	file, err := os.Open(filepath)
	if err != nil {
		if os.IsNotExist(err) {
			return "", nil
		}
		return "", err
	}
	defer file.Close()
	
	content, err := os.ReadFile(filepath)
	if err != nil {
		return "", err
	}
	
	return string(content), nil
}

// findDataSectionStart 找到数据部分的开始位置
func findDataSectionStart(content string) int {
	lines := strings.Split(content, "\n")
	
	for i, line := range lines {
		trimmed := strings.TrimSpace(line)
		// 数据行以非注释、非元数据的制表符分隔内容开始
		if trimmed != "" &&
		   !strings.HasPrefix(trimmed, "#") &&
		   !strings.HasPrefix(trimmed, "---") &&
		   !strings.HasPrefix(trimmed, "...") &&
		   !strings.HasPrefix(trimmed, "name:") &&
		   !strings.HasPrefix(trimmed, "version:") &&
		   !strings.HasPrefix(trimmed, "sort:") &&
		   !strings.HasPrefix(trimmed, "columns:") &&
		   !strings.HasPrefix(trimmed, "encoder:") &&
		   !strings.HasPrefix(trimmed, "exclude_patterns:") &&
		   !strings.HasPrefix(trimmed, "rules:") &&
		   strings.Contains(trimmed, "\t") {
			// 返回这个数据行之前的所有内容
			pos := 0
			for j := 0; j < i; j++ {
				pos += len(lines[j]) + 1 // +1 for newline
			}
			return pos
		}
	}
	
	return -1
}

// getDefaultHeader 根据文件名返回默认头部信息
func getDefaultHeader(filePath string) string {
	filename := filepath.Base(filePath)
	
	var name string
	var description string
	
	switch filename {
	case "LL.chars.quick.dict.yaml":
		name = "LL.chars.quick"
		description = "离乱单字简码"
	case "LL.chars.full.dict.yaml":
		name = "LL.chars.full"
		description = "离乱单字全码"
	case "LL.words.quick.dict.yaml":
		name = "LL.words.quick"
		description = "离乱词简码"
	case "LL.words.full.dict.yaml":
		name = "LL.words.full"
		description = "离乱词全码"
	case "LL_chaifen.dict.yaml":
		name = "LL_chaifen"
		description = "离乱拆分注释"
	default:
		name = "default"
		description = "离乱字典文件"
	}
	
	return fmt.Sprintf(`# encoding: utf-8
#
# %s
# 版本: 20251001
#

---
name: %s
version: 0x00
sort: original
columns:
  - text
  - code
encoder:
  exclude_patterns:
    - "^[a-z,./]$" # 一简
    - "^[a-z,./][wruo]$"
    #- "^.{1}$"
    #- "^.{1}[wruo]$"
  rules:
    - length_equal: 2
      formula: "AaAbBaBb"
    - length_equal: 3
      formula: "AaBaCaCb"
    - length_in_range: [4, 20]
      formula: "AaBaCaZa"
`, description, name)
}

// LoadFullDictMap 从LL.chars.full.dict.yaml码表文件加载字符映射
func LoadFullDictMap(dictFilePath string) (map[string][]string, error) {
	file, err := os.Open(dictFilePath)
	if err != nil {
		return nil, fmt.Errorf("打开码表文件失败: %w", err)
	}
	defer file.Close()

	codeCharMap := make(map[string][]string)
	scanner := bufio.NewScanner(file)
	
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		// 跳过注释和元数据行
		if line == "" || strings.HasPrefix(line, "#") || strings.HasPrefix(line, "---") ||
		   strings.HasPrefix(line, "...") || strings.HasPrefix(line, "name:") ||
		   strings.HasPrefix(line, "version:") || strings.HasPrefix(line, "sort:") ||
		   strings.HasPrefix(line, "columns:") || strings.HasPrefix(line, "encoder:") ||
		   strings.HasPrefix(line, "  - ") || strings.HasPrefix(line, "  exclude_patterns:") ||
		   strings.HasPrefix(line, "  rules:") {
			continue
		}
		
		// 解析数据行：字符\t编码
		fields := strings.Split(line, "\t")
		if len(fields) >= 2 {
			char := fields[0]
			code := fields[1]
			codeCharMap[code] = append(codeCharMap[code], char)
		}
	}
	
	if err := scanner.Err(); err != nil {
		return nil, fmt.Errorf("读取码表文件失败: %w", err)
	}
	
	return codeCharMap, nil
}

// BuildPresetData 根据单字简码表和全码表生成 preset_data.txt
func BuildPresetData(simpleCodeList []*types.CharMeta, fullCodeMetaList []*types.CharMeta) ([]string, error) {
	// 尝试从deploy/tmp/LL.chars.full.dict.yaml码表文件加载字符映射
	fullDictPath := "../deploy/tmp/LL.chars.full.dict.yaml"
	codeCharMap, err := LoadFullDictMap(fullDictPath)
	if err != nil {
		// 如果码表文件不存在，回退到使用fullCodeMetaList
		codeCharMap = make(map[string][]string)
		for _, charMeta := range fullCodeMetaList {
			codeCharMap[charMeta.Code] = append(codeCharMap[charMeta.Code], charMeta.Char)
		}
	}
	
	// 按前缀分组（使用简码表）
	prefixGroups := make(map[string][]*types.CharMeta)
	
	for _, charMeta := range simpleCodeList {
		code := charMeta.Code
		// 只有当编码长度大于1时才有前缀
		if len(code) > 1 {
			prefix := code[:len(code)-1]  // 去掉最后一个字符作为前缀
			prefixGroups[prefix] = append(prefixGroups[prefix], charMeta)
		}
	}
	
	// 生成输出行
	outputLines := make([]string, 0, len(prefixGroups))
	
	for prefix, chars := range prefixGroups {
		// 按照末码类型将字符分类
		wChars := make([]string, 0)
		rChars := make([]string, 0)
		uChars := make([]string, 0)
		oChars := make([]string, 0)
		
		for _, charMeta := range chars {
			code := charMeta.Code
			lastChar := string(code[len(code)-1])
			
			switch lastChar {
			case "w":
				wChars = append(wChars, charMeta.Char)
			case "r":
				rChars = append(rChars, charMeta.Char)
			case "u":
				uChars = append(uChars, charMeta.Char)
			case "o":
				oChars = append(oChars, charMeta.Char)
			}
		}
		
		// 固定的后缀顺序：w, r, u, o
		suffixes := []string{"w", "r", "u", "o"}
		
		// 构建候选项
		candidates := make([]string, 0, 4)
		for _, suffix := range suffixes {
			var candidate string
			switch suffix {
			case "w":
				if len(wChars) > 0 {
					candidate = suffix + wChars[0]
				} else {
					candidate = suffix + "①"
				}
			case "r":
				if len(rChars) > 0 {
					candidate = suffix + rChars[0]
				} else {
					candidate = suffix + "②"
				}
			case "u":
				if len(uChars) > 0 {
					candidate = suffix + uChars[0]
				} else {
					candidate = suffix + "③"
				}
			case "o":
				if len(oChars) > 0 {
					candidate = suffix + oChars[0]
				} else {
					candidate = suffix + "④"
				}
			}
			candidates = append(candidates, candidate)
		}
		
		// 将四个候选项用空格连接
		candidateStr := strings.Join(candidates, " ")
		outputLine := candidateStr + "\t" + prefix
		outputLines = append(outputLines, outputLine)
	}
	
	// 添加三码组合（",,,~zzz"）的13824个组合
	outputLines = append(outputLines, generateThreeCodeCombinations(codeCharMap)...)
	
	// 按编码（code）升序排列
	sort.Slice(outputLines, func(i, j int) bool {
		// 提取每行的编码部分（制表符后的内容）
		partsI := strings.Split(outputLines[i], "\t")
		partsJ := strings.Split(outputLines[j], "\t")
		if len(partsI) >= 2 && len(partsJ) >= 2 {
			return partsI[1] < partsJ[1]
		}
		return outputLines[i] < outputLines[j]
	})

	return outputLines, nil
}

// generateThreeCodeCombinations 生成三码组合的数据，使用实际字符或占位符
func generateThreeCodeCombinations(codeCharMap map[string][]string) []string {
	// 24个键：qtypasdfghjkl;zxcvbnm,./
	keys := []string{"q", "t", "y", "p", "a", "s", "d", "f", "g", "h", "j", "k", "l", ";", "z", "x", "c", "v", "b", "n", "m", ",", ".", "/"}
	
	outputLines := make([]string, 0, 24*24*24) // 13824个组合
	
	// 生成所有三码组合
	for _, first := range keys {
		for _, second := range keys {
			for _, third := range keys {
				prefix := first + second + third
				
				// 查找对应四个后缀的实际字符
				wChar := findCharForCodeFromDict(codeCharMap, prefix+"w")
				rChar := findCharForCodeFromDict(codeCharMap, prefix+"r")
				uChar := findCharForCodeFromDict(codeCharMap, prefix+"u")
				oChar := findCharForCodeFromDict(codeCharMap, prefix+"o")
				
				// 构建候选项
				candidates := make([]string, 0, 4)
				if wChar != "" {
					candidates = append(candidates, "w"+wChar)
				} else {
					candidates = append(candidates, "w①")
				}
				if rChar != "" {
					candidates = append(candidates, "r"+rChar)
				} else {
					candidates = append(candidates, "r②")
				}
				if uChar != "" {
					candidates = append(candidates, "u"+uChar)
				} else {
					candidates = append(candidates, "u③")
				}
				if oChar != "" {
					candidates = append(candidates, "o"+oChar)
				} else {
					candidates = append(candidates, "o④")
				}
				
				candidateStr := strings.Join(candidates, " ")
				outputLine := candidateStr + "\t" + prefix
				outputLines = append(outputLines, outputLine)
			}
		}
	}
	
	return outputLines
}

// findCharForCodeFromDict 在码表映射中查找对应编码的字符
func findCharForCodeFromDict(codeCharMap map[string][]string, code string) string {
	if chars, exists := codeCharMap[code]; exists && len(chars) > 0 {
		// 返回重码组内最上方的字符（码表文件中的第一个字符）
		return chars[0]
	}
	return ""
}

// GenerateRootsDict 根据ll_map.txt生成字根码表并追加到LL.roots.dict.yaml
// llMapFile: ll_map.txt文件路径，格式为"字根编码\t字根"
// rootsDictFile: LL.roots.dict.yaml文件路径
func GenerateRootsDict(llMapFile, rootsDictFile string) error {
	// 读取ll_map.txt文件
	file, err := os.Open(llMapFile)
	if err != nil {
		return fmt.Errorf("读取ll_map.txt文件失败: %w", err)
	}
	defer file.Close()

	// 解析ll_map.txt内容
	var rootsEntries []*DictEntry
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}

		// 格式为"字根编码\t字根"
		fields := strings.Split(line, "\t")
		if len(fields) < 2 {
			continue
		}

		code := fields[0]
		root := fields[1]

		// 转换为"字根\t\]字根编码"格式
		transformedCode := "]" + code
		
		rootsEntries = append(rootsEntries, &DictEntry{
			Text: root,
			Code: transformedCode,
			Freq: 0, // 字根没有词频
		})
	}

	if err := scanner.Err(); err != nil {
		return fmt.Errorf("扫描ll_map.txt文件失败: %w", err)
	}

	// 构建要追加的内容，保持ll_map.txt的原始顺序
	var contentToAppend strings.Builder
	for _, entry := range rootsEntries {
		contentToAppend.WriteString(fmt.Sprintf("%s\t%s\n", entry.Text, entry.Code))
	}

	// 追加到目标文件
	err = appendToFile(rootsDictFile, contentToAppend.String())
	if err != nil {
		return fmt.Errorf("追加到LL.roots.dict.yaml失败: %w", err)
	}

	return nil
}

// generatePlaceholders 生成占位符
// startIndex: 占位符起始编号（从1开始）
// count: 需要生成的占位符数量
// maxLimit: 该简码长度的最大限制数
func generatePlaceholders(startIndex, count, maxLimit int) []string {
	if count <= 0 || startIndex > maxLimit {
		return nil
	}
	
	// 根据最大限制数确定占位符字符集
	var placeholders []string
	switch maxLimit {
	case 1:
		placeholders = []string{"①"}
	case 2:
		placeholders = []string{"①", "②"}
	case 3:
		placeholders = []string{"①", "②", "③"}
	case 4:
		placeholders = []string{"①", "②", "③", "④"}
	case 5:
		placeholders = []string{"①", "②", "③", "④", "⑤"}
	case 6:
		placeholders = []string{"①", "②", "③", "④", "⑤", "⑥"}
	case 7:
		placeholders = []string{"①", "②", "③", "④", "⑤", "⑥", "⑦"}
	case 8:
		placeholders = []string{"①", "②", "③", "④", "⑤", "⑥", "⑦", "⑧"}
	case 9:
		placeholders = []string{"①", "②", "③", "④", "⑤", "⑥", "⑦", "⑧", "⑨"}
	case 10:
		placeholders = []string{"①", "②", "③", "④", "⑤", "⑥", "⑦", "⑧", "⑨", "⑩"}
	default:
		// 对于超过10的情况，使用数字加括号
		placeholders = make([]string, maxLimit)
		for i := 0; i < maxLimit; i++ {
			placeholders[i] = fmt.Sprintf("(%d)", i+1)
		}
	}
	
	// 从startIndex开始取count个占位符
	if startIndex > len(placeholders) {
		return nil
	}
	
	endIndex := startIndex + count - 1
	if endIndex > len(placeholders) {
		endIndex = len(placeholders)
		count = endIndex - startIndex + 1
	}
	
	if count <= 0 {
		return nil
	}
	
	return placeholders[startIndex-1 : startIndex-1+count]
}
