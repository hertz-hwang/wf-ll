package tools

import (
	"bufio"
	"fmt"
	"os"
	"sort"
	"strconv"
	"strings"
)

// CitiEntry 表示一个编码条目
type CitiEntry struct {
	Text     string // 字或词
	Code     string // 编码
	Freq     int64  // 词频
	Source   string // 来源文件标识
}

// ReadCitiFile 读取编码文件并解析为CitiEntry列表
func ReadCitiFile(filepath string, source string) ([]*CitiEntry, error) {
	file, err := os.Open(filepath)
	if err != nil {
		return nil, fmt.Errorf("无法打开文件 %s: %w", filepath, err)
	}
	defer file.Close()

	var entries []*CitiEntry
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := scanner.Text()

		// 检查空行：只检查是否完全为空（包括空白字符）
		if strings.TrimSpace(line) == "" {
			continue
		}

		// 检查注释行：先清理空白再检查
		if strings.HasPrefix(strings.TrimSpace(line), "#") {
			continue
		}

		fields := strings.Split(line, "\t")
		if len(fields) < 2 {
			continue
		}

		entry := &CitiEntry{
			Text:   fields[0],
			Code:   fields[1],
			Source: source,
		}

		// 如果有第三列，解析词频
		if len(fields) >= 3 {
			freq, err := strconv.ParseInt(fields[2], 10, 64)
			if err == nil {
				entry.Freq = freq
			}
		}

		entries = append(entries, entry)
	}

	if err := scanner.Err(); err != nil {
		return nil, fmt.Errorf("读取文件 %s 时出错: %w", filepath, err)
	}

	return entries, nil
}

// SortByFreq 按词频降序排序
func SortByFreq(entries []*CitiEntry) {
	sort.Slice(entries, func(i, j int) bool {
		return entries[i].Freq > entries[j].Freq
	})
}

// WriteCitiFile 将CitiEntry列表写入文件
func WriteCitiFile(filepath string, entries []*CitiEntry) error {
	file, err := os.Create(filepath)
	if err != nil {
		return fmt.Errorf("无法创建文件 %s: %w", filepath, err)
	}
	defer file.Close()

	writer := bufio.NewWriter(file)
	for _, entry := range entries {
		line := fmt.Sprintf("%s\t%s\t%d\n", entry.Text, entry.Code, entry.Freq)
		if _, err := writer.WriteString(line); err != nil {
			return fmt.Errorf("写入文件 %s 时出错: %w", filepath, err)
		}
	}

	if err := writer.Flush(); err != nil {
		return fmt.Errorf("刷新文件 %s 时出错: %w", filepath, err)
	}

	return nil
}

// ProcessCitiFiles 处理四个编码文件：按词频重排
func ProcessCitiFiles(charsSimpFile, charsFullFile, wordsSimpFile, wordsFullFile string) error {
	// 读取四个文件
	charsSimpEntries, err := ReadCitiFile(charsSimpFile, "chars_simp")
	if err != nil {
		return fmt.Errorf("读取单字简码文件失败: %w", err)
	}

	charsFullEntries, err := ReadCitiFile(charsFullFile, "chars_full")
	if err != nil {
		return fmt.Errorf("读取单字全码文件失败: %w", err)
	}

	wordsSimpEntries, err := ReadCitiFile(wordsSimpFile, "words_simp")
	if err != nil {
		return fmt.Errorf("读取多字词简码文件失败: %w", err)
	}

	wordsFullEntries, err := ReadCitiFile(wordsFullFile, "words_full")
	if err != nil {
		return fmt.Errorf("读取多字词全码文件失败: %w", err)
	}

	// 按词频重排
	SortByFreq(charsSimpEntries)
	SortByFreq(charsFullEntries)
	SortByFreq(wordsSimpEntries)
	SortByFreq(wordsFullEntries)

	// 写回原文件
	if err := WriteCitiFile(charsSimpFile, charsSimpEntries); err != nil {
		return fmt.Errorf("写入单字简码文件失败: %w", err)
	}

	if err := WriteCitiFile(charsFullFile, charsFullEntries); err != nil {
		return fmt.Errorf("写入单字全码文件失败: %w", err)
	}

	if err := WriteCitiFile(wordsSimpFile, wordsSimpEntries); err != nil {
		return fmt.Errorf("写入多字词简码文件失败: %w", err)
	}

	if err := WriteCitiFile(wordsFullFile, wordsFullEntries); err != nil {
		return fmt.Errorf("写入多字词全码文件失败: %w", err)
	}

	return nil
}

// CombineCitiFiles 将四个文件按照指定顺序拼接在一起
func CombineCitiFiles(charsSimpFile, charsFullFile, wordsSimpFile, wordsFullFile string) ([]*CitiEntry, error) {
	var allEntries []*CitiEntry

	// 按照指定顺序读取四个文件
	files := []struct {
		path   string
		source string
	}{
		{charsSimpFile, "chars_simp"},
		{charsFullFile, "chars_full"},
		{wordsSimpFile, "words_simp"},
		{wordsFullFile, "words_full"},
	}

	for _, file := range files {
		entries, err := ReadCitiFile(file.path, file.source)
		if err != nil {
			return nil, fmt.Errorf("读取文件 %s 失败: %w", file.path, err)
		}
		allEntries = append(allEntries, entries...)
	}

	return allEntries, nil
}

// CombineAllCitiFiles 按照指定顺序组合所有文件：ll_citi_pre + 四个编码文件
func CombineAllCitiFiles(citiPreFile, charsSimpFile, charsFullFile, wordsSimpFile, wordsFullFile string) ([]*CitiEntry, error) {
	var allEntries []*CitiEntry

	// 1. 首先读取现有的ll_citi_pre.txt内容
	existingEntries, err := ReadCitiFile(citiPreFile, "citi_pre")
	if err != nil && !os.IsNotExist(err) {
		return nil, fmt.Errorf("读取现有文件失败: %w", err)
	}
	allEntries = append(allEntries, existingEntries...)

	// 2. 然后按照指定顺序读取四个编码文件
	files := []struct {
		path   string
		source string
	}{
		{charsSimpFile, "chars_simp"},
		{charsFullFile, "chars_full"},
		{wordsSimpFile, "words_simp"},
		{wordsFullFile, "words_full"},
	}

	for _, file := range files {
		entries, err := ReadCitiFile(file.path, file.source)
		if err != nil {
			return nil, fmt.Errorf("读取文件 %s 失败: %w", file.path, err)
		}
		allEntries = append(allEntries, entries...)
	}

	return allEntries, nil
}

// AppendToCitiPre 将合并的条目追加到ll_citi_pre.txt
func AppendToCitiPre(entries []*CitiEntry, citiPreFile string) error {
	// 读取现有的ll_citi_pre.txt内容
	existingEntries, err := ReadCitiFile(citiPreFile, "existing")
	if err != nil && !os.IsNotExist(err) {
		return fmt.Errorf("读取现有文件失败: %w", err)
	}

	// 合并现有条目和新条目
	allEntries := append(existingEntries, entries...)

	// 写入文件
	file, err := os.Create(citiPreFile)
	if err != nil {
		return fmt.Errorf("创建文件失败: %w", err)
	}
	defer file.Close()

	writer := bufio.NewWriter(file)
	for _, entry := range allEntries {
		line := fmt.Sprintf("%s\t%s\n", entry.Text, entry.Code)
		if _, err := writer.WriteString(line); err != nil {
			return fmt.Errorf("写入文件失败: %w", err)
		}
	}

	if err := writer.Flush(); err != nil {
		return fmt.Errorf("刷新文件失败: %w", err)
	}

	return nil
}

// CreateGendaCiti 创建genda_citi.txt并删除词频
func CreateGendaCiti(entries []*CitiEntry, gendaCitiFile string) error {
	file, err := os.Create(gendaCitiFile)
	if err != nil {
		return fmt.Errorf("创建文件失败: %w", err)
	}
	defer file.Close()

	writer := bufio.NewWriter(file)
	for _, entry := range entries {
		line := fmt.Sprintf("%s\t%s\n", entry.Text, entry.Code)
		if _, err := writer.WriteString(line); err != nil {
			return fmt.Errorf("写入文件失败: %w", err)
		}
	}

	if err := writer.Flush(); err != nil {
		return fmt.Errorf("刷新文件失败: %w", err)
	}

	return nil
}

// AddCandidateCodes 为重复编码添加候选码，保持原始文件顺序
func AddCandidateCodes(entries []*CitiEntry) []*CitiEntry {
	// 按编码分组，但记录每个条目的原始位置
	type entryWithIndex struct {
		entry *CitiEntry
		index int
	}
	codeGroups := make(map[string][]*entryWithIndex)
	
	for i, entry := range entries {
		codeGroups[entry.Code] = append(codeGroups[entry.Code], &entryWithIndex{entry, i})
	}

	// 创建结果数组，保持原始顺序
	result := make([]*CitiEntry, len(entries))
	candidateSuffixes := []string{"e", "i", "[", "2", "3", "7", "8", "9", "0"}

	// 处理每个编码的重码情况
	for code, group := range codeGroups {
		if len(group) == 1 {
			// 没有重码，检查编码类型
			if len(code) == 4 {
				// 四码多字词：编码长度为4，使用28个键（qwrtyuopasdfghjkl;zxcvbnm,./）
				// 四码多字词首选使用原编码，不添加"_"后缀
				newEntry := &CitiEntry{
					Text:   group[0].entry.Text,
					Code:   code,
					Freq:   group[0].entry.Freq,
					Source: group[0].entry.Source,
				}
				result[group[0].index] = newEntry
			} else {
				// 简码：编码长度1~3位，为简码添加"_"后缀
				newEntry := &CitiEntry{
					Text:   group[0].entry.Text,
					Code:   code + "_",
					Freq:   group[0].entry.Freq,
					Source: group[0].entry.Source,
				}
				result[group[0].index] = newEntry
			}
			continue
		}

		// 有重码，按词频排序（保持词频排序）
		sort.Slice(group, func(i, j int) bool {
			return group[i].entry.Freq > group[j].entry.Freq
		})

		// 为每个候选添加后缀，保持原始位置
		for i, ew := range group {
			var newCode string
			if i == 0 {
				// 首选：检查编码类型
				if len(code) == 4 {
					// 四码多字词首选使用原编码，不添加后缀
					newCode = code
				} else {
					// 简码首选添加"_"后缀
					newCode = code + "_"
				}
			} else if i < 10 {
				// 前10个候选使用单字符后缀（从e开始，跳过_）
				// i=1对应e, i=2对应i, ..., i=9对应0
				newCode = code + candidateSuffixes[i-1]
			} else {
				// 第11个及以后的候选使用翻页格式
				page := (i - 10) / 9  // 每页9个候选
				posInPage := (i - 10) % 9
				// 第1页：=e, =i, =[, =2, =3, =7, =8, =9, =0
				// 第2页：==e, ==i, ==[, ==2, ==3, ==7, ==8, ==9, ==0
				// 第3页：===e, ===i, 以此类推...
				equals := strings.Repeat("=", page+1)
				newCode = fmt.Sprintf("%s%s%s", code, equals, candidateSuffixes[posInPage])
			}

			newEntry := &CitiEntry{
				Text:   ew.entry.Text,
				Code:   newCode,
				Freq:   ew.entry.Freq,
				Source: ew.entry.Source,
			}
			result[ew.index] = newEntry
		}
	}

	// 移除可能为nil的条目（理论上不应该有）
	finalResult := make([]*CitiEntry, 0, len(entries))
	for _, entry := range result {
		if entry != nil {
			finalResult = append(finalResult, entry)
		}
	}

	return finalResult
}

// AddCandidateCodesWithSimpleSorting 为重复编码添加候选码，在应用出简让全逻辑后添加补码后缀
func AddCandidateCodesWithSimpleSorting(entries []*CitiEntry) []*CitiEntry {
	// 按编码分组
	codeGroups := make(map[string][]*CitiEntry)
	
	for _, entry := range entries {
		codeGroups[entry.Code] = append(codeGroups[entry.Code], entry)
	}

	// 创建结果数组
	result := make([]*CitiEntry, 0, len(entries))
	candidateSuffixes := []string{"e", "i", "[", "2", "3", "7", "8", "9", "0"}

	// 处理每个编码的重码情况
	for code, group := range codeGroups {
		if len(group) == 1 {
			// 没有重码，检查编码类型
			if len(code) == 4 {
				// 四码多字词：编码长度为4，使用28个键（qwrtyuopasdfghjkl;zxcvbnm,./）
				// 四码多字词首选使用原编码，不添加"_"后缀
				newEntry := &CitiEntry{
					Text:   group[0].Text,
					Code:   code,
					Freq:   group[0].Freq,
					Source: group[0].Source,
				}
				result = append(result, newEntry)
			} else {
				// 简码：编码长度1~3位，为简码添加"_"后缀
				newEntry := &CitiEntry{
					Text:   group[0].Text,
					Code:   code + "_",
					Freq:   group[0].Freq,
					Source: group[0].Source,
				}
				result = append(result, newEntry)
			}
			continue
		}

		// 有重码，按当前顺序（已经应用了出简让全逻辑）添加后缀
		for i, entry := range group {
			var newCode string
			if i == 0 {
				// 首选：检查编码类型
				if len(code) == 4 {
					// 四码多字词首选使用原编码，不添加后缀
					newCode = code
				} else {
					// 简码首选添加"_"后缀
					newCode = code + "_"
				}
			} else if i < 10 {
				// 前10个候选使用单字符后缀（从e开始，跳过_）
				// i=1对应e, i=2对应i, ..., i=9对应0
				newCode = code + candidateSuffixes[i-1]
			} else {
				// 第11个及以后的候选使用翻页格式
				page := (i - 10) / 9  // 每页9个候选
				posInPage := (i - 10) % 9
				// 第1页：=e, =i, =[, =2, =3, =7, =8, =9, =0
				// 第2页：==e, ==i, ==[, ==2, ==3, ==7, ==8, ==9, ==0
				// 第3页：===e, ===i, 以此类推...
				equals := strings.Repeat("=", page+1)
				newCode = fmt.Sprintf("%s%s%s", code, equals, candidateSuffixes[posInPage])
			}

			newEntry := &CitiEntry{
				Text:   entry.Text,
				Code:   newCode,
				Freq:   entry.Freq,
				Source: entry.Source,
			}
			result = append(result, newEntry)
		}
	}

	return result
}

// ProcessCitiFilesComplete 完整的citi文件处理流程
func ProcessCitiFilesComplete(charsSimpFile, charsFullFile, wordsSimpFile, wordsFullFile, citiPreFile, gendaCitiFile string) error {
	// 按照指定顺序分别处理每个来源，保持各自原始排序
	var allEntries []*CitiEntry

	// 1. 首先处理ll_citi_pre.txt - 不进行重码处理，保持原有顺序
	citiPreEntries, err := ReadCitiFile(citiPreFile, "citi_pre")
	if err != nil && !os.IsNotExist(err) {
		return fmt.Errorf("读取ll_citi_pre.txt失败: %w", err)
	}
	// ll_citi_pre.txt已经包含候选编码补码，直接使用
	allEntries = append(allEntries, citiPreEntries...)

	// 2. 然后处理code_chars_simp.txt - 不需要运用补码规则，直接使用
	charsSimpEntries, err := ReadCitiFile(charsSimpFile, "chars_simp")
	if err != nil {
		return fmt.Errorf("读取code_chars_simp.txt失败: %w", err)
	}
	allEntries = append(allEntries, charsSimpEntries...)

	// 3. 接着处理code_chars_full.txt - 需要运用补码规则，并应用出简让全逻辑
	charsFullEntries, err := ReadCitiFile(charsFullFile, "chars_full")
	if err != nil {
		return fmt.Errorf("读取code_chars_full.txt失败: %w", err)
	}
	
	// 对单字全码应用出简让全逻辑，然后添加补码后缀
	charsFullEntries = applySimpleCharsSortingToCiti(charsFullEntries)
	charsFullWithCandidates := AddCandidateCodesWithSimpleSorting(charsFullEntries)
	allEntries = append(allEntries, charsFullWithCandidates...)

	// 4. 然后处理code_words_simp.txt - 需要运用补码规则
	wordsSimpEntries, err := ReadCitiFile(wordsSimpFile, "words_simp")
	if err != nil {
		return fmt.Errorf("读取code_words_simp.txt失败: %w", err)
	}
	wordsSimpWithCandidates := AddCandidateCodes(wordsSimpEntries)
	allEntries = append(allEntries, wordsSimpWithCandidates...)

	// 5. 最后处理code_words_full.txt - 需要运用补码规则
	wordsFullEntries, err := ReadCitiFile(wordsFullFile, "words_full")
	if err != nil {
		return fmt.Errorf("读取code_words_full.txt失败: %w", err)
	}
	wordsFullWithCandidates := AddCandidateCodes(wordsFullEntries)
	allEntries = append(allEntries, wordsFullWithCandidates...)

	// 创建genda_citi.txt并删除词频
	if err := CreateGendaCiti(allEntries, gendaCitiFile); err != nil {
		return fmt.Errorf("创建genda_citi.txt失败: %w", err)
	}

	return nil
}

// ProcessCitiFilesWithLinglong 使用玲珑词库的完整citi文件处理流程
func ProcessCitiFilesWithLinglong(charsSimpFile, charsFullFile, linglongQuickFile, linglongFullFile, citiPreFile, gendaCitiFile string) error {
	// 按照指定顺序分别处理每个来源，保持各自原始排序
	var allEntries []*CitiEntry

	// 1. 首先处理ll_citi_pre.txt - 不进行重码处理，保持原有顺序
	citiPreEntries, err := ReadCitiFile(citiPreFile, "citi_pre")
	if err != nil && !os.IsNotExist(err) {
		return fmt.Errorf("读取ll_citi_pre.txt失败: %w", err)
	}
	// ll_citi_pre.txt已经包含候选编码补码，直接使用
	allEntries = append(allEntries, citiPreEntries...)

	// 2. 然后处理code_chars_simp.txt - 不需要运用补码规则，直接使用
	charsSimpEntries, err := ReadCitiFile(charsSimpFile, "chars_simp")
	if err != nil {
		return fmt.Errorf("读取code_chars_simp.txt失败: %w", err)
	}
	allEntries = append(allEntries, charsSimpEntries...)

	// 3. 接着处理code_chars_full.txt - 需要运用补码规则，并应用出简让全逻辑
	charsFullEntries, err := ReadCitiFile(charsFullFile, "chars_full")
	if err != nil {
		return fmt.Errorf("读取code_chars_full.txt失败: %w", err)
	}
	
	// 对单字全码应用出简让全逻辑，然后添加补码后缀
	charsFullEntries = applySimpleCharsSortingToCiti(charsFullEntries)
	charsFullWithCandidates := AddCandidateCodesWithSimpleSorting(charsFullEntries)
	allEntries = append(allEntries, charsFullWithCandidates...)

	// 4. 然后处理LL_linglong.quick.dict.yaml - 需要运用补码规则
	linglongQuickEntries, err := ReadCitiFile(linglongQuickFile, "LL_linglong.quick")
	if err != nil {
		return fmt.Errorf("读取LL_linglong.quick.dict.yaml失败: %w", err)
	}
	linglongQuickWithCandidates := AddCandidateCodes(linglongQuickEntries)
	allEntries = append(allEntries, linglongQuickWithCandidates...)

	// 5. 最后处理LL_linglong.full.dict.yaml - 需要运用补码规则
	linglongFullEntries, err := ReadCitiFile(linglongFullFile, "LL_linglong.full")
	if err != nil {
		return fmt.Errorf("读取LL_linglong.full.dict.yaml失败: %w", err)
	}
	linglongFullWithCandidates := AddCandidateCodes(linglongFullEntries)
	allEntries = append(allEntries, linglongFullWithCandidates...)

	// 创建genda_citi.txt并删除词频
	if err := CreateGendaCiti(allEntries, gendaCitiFile); err != nil {
		return fmt.Errorf("创建genda_citi.txt失败: %w", err)
	}

	return nil
}

// CreateDazhuCode 根据genda_citi.txt生成dazhu_code.txt，格式为"编码\t字词"
func CreateDazhuCode(gendaCitiFile, dazhuCodeFile string, maxSizeMB int) error {
	// 读取genda_citi.txt文件
	entries, err := ReadCitiFile(gendaCitiFile, "genda_citi")
	if err != nil {
		return fmt.Errorf("读取genda_citi.txt失败: %w", err)
	}

	// 创建输出文件
	file, err := os.Create(dazhuCodeFile)
	if err != nil {
		return fmt.Errorf("创建文件失败: %w", err)
	}
	defer file.Close()

	writer := bufio.NewWriter(file)
	maxSizeBytes := maxSizeMB * 1024 * 1024
	currentSize := 0

	// 按"编码\t字词"格式写入，并控制文件大小
	for _, entry := range entries {
		line := fmt.Sprintf("%s\t%s\n", entry.Code, entry.Text)
		lineSize := len([]byte(line))
		
		// 检查是否超过最大文件大小
		if currentSize+lineSize > maxSizeBytes {
			break
		}
		
		if _, err := writer.WriteString(line); err != nil {
			return fmt.Errorf("写入文件失败: %w", err)
		}
		currentSize += lineSize
	}

	if err := writer.Flush(); err != nil {
		return fmt.Errorf("刷新文件失败: %w", err)
	}

	return nil
}

// applySimpleCharsSortingToCiti 对CitiEntry列表应用出简让全排序逻辑
func applySimpleCharsSortingToCiti(entries []*CitiEntry) []*CitiEntry {
	// 按编码分组
	groups := make(map[string][]*CitiEntry)
	codeOrder := make([]string, 0)
	
	for _, entry := range entries {
		if _, exists := groups[entry.Code]; !exists {
			codeOrder = append(codeOrder, entry.Code)
		}
		groups[entry.Code] = append(groups[entry.Code], entry)
	}
	
	// 对每个编码组进行特殊处理
	result := make([]*CitiEntry, 0, len(entries))
	for _, code := range codeOrder {
		group := groups[code]
		processedGroup := processCitiCodeGroup(group)
		result = append(result, processedGroup...)
	}
	
	return result
}

// processCitiCodeGroup 处理单个编码组的简码汉字特殊排序
func processCitiCodeGroup(group []*CitiEntry) []*CitiEntry {
	if len(group) < 3 {
		// 如果重码组内候选不足三个，不应用特殊规则
		return group
	}
	
	// 读取简码信息
	simpleChars := loadSimpleCharsForCiti()
	
	// 创建副本进行处理，避免影响原始数据
	result := make([]*CitiEntry, len(group))
	copy(result, group)
	
	// 第一步：处理一简汉字，下移2行
	result = moveSimpleCharsInCiti(result, simpleChars, 1, 2)
	
	// 第二步：处理二简汉字，下移2行
	result = moveSimpleCharsInCiti(result, simpleChars, 2, 2)
	
	// 第三步：处理"的"、"了"二字，下移2位
	result = moveSpecialCharsInCiti(result)
	
	return result
}

// loadSimpleCharsForCiti 从code_chars_simp.txt加载简码汉字信息
func loadSimpleCharsForCiti() map[string]int {
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

// moveSimpleCharsInCiti 在CitiEntry列表中移动简码汉字
func moveSimpleCharsInCiti(group []*CitiEntry, simpleChars map[string]int, simpleType int, moveCount int) []*CitiEntry {
	result := make([]*CitiEntry, len(group))
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

// moveSpecialCharsInCiti 在CitiEntry列表中移动特殊字符"的"和"了"
func moveSpecialCharsInCiti(group []*CitiEntry) []*CitiEntry {
	result := make([]*CitiEntry, len(group))
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

// ProcessCitiFilesWithLinglongNoSimple 使用玲珑词库的无简词版citi文件处理流程
func ProcessCitiFilesWithLinglongNoSimple(charsSimpFile, charsFullFile, linglongQuickFile, linglongFullFile, citiPreFile, gendaCitiFile string) error {
	// 按照指定顺序分别处理每个来源，保持各自原始排序
	var allEntries []*CitiEntry

	// 1. 首先处理ll_citi_pre.txt - 不进行重码处理，保持原有顺序
	citiPreEntries, err := ReadCitiFile(citiPreFile, "citi_pre")
	if err != nil && !os.IsNotExist(err) {
		return fmt.Errorf("读取ll_citi_pre.txt失败: %w", err)
	}
	// ll_citi_pre.txt已经包含候选编码补码，直接使用
	allEntries = append(allEntries, citiPreEntries...)

	// 2. 然后处理code_chars_simp.txt - 不需要运用补码规则，直接使用
	charsSimpEntries, err := ReadCitiFile(charsSimpFile, "chars_simp")
	if err != nil {
		return fmt.Errorf("读取code_chars_simp.txt失败: %w", err)
	}
	allEntries = append(allEntries, charsSimpEntries...)

	// 3. 接着处理code_chars_full.txt - 需要运用补码规则，并应用出简让全逻辑
	charsFullEntries, err := ReadCitiFile(charsFullFile, "chars_full")
	if err != nil {
		return fmt.Errorf("读取code_chars_full.txt失败: %w", err)
	}
	
	// 对单字全码应用出简让全逻辑，然后添加补码后缀
	charsFullEntries = applySimpleCharsSortingToCiti(charsFullEntries)
	charsFullWithCandidates := AddCandidateCodesWithSimpleSorting(charsFullEntries)
	allEntries = append(allEntries, charsFullWithCandidates...)

	// 4. 最后处理LL_linglong.full.dict.yaml - 需要运用补码规则
	linglongFullEntries, err := ReadCitiFile(linglongFullFile, "LL_linglong.full")
	if err != nil {
		return fmt.Errorf("读取LL_linglong.full.dict.yaml失败: %w", err)
	}
	linglongFullWithCandidates := AddCandidateCodes(linglongFullEntries)
	allEntries = append(allEntries, linglongFullWithCandidates...)

	// 创建genda_citi.txt并删除词频
	if err := CreateGendaCiti(allEntries, gendaCitiFile); err != nil {
		return fmt.Errorf("创建genda_citi.txt失败: %w", err)
	}

	return nil
}