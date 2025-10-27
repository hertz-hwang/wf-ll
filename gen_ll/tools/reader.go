package tools

import (
	"fmt"
	"os"
	"regexp"
	"strconv"
	"strings"
	"sync"

	"gen_ll/types"
)

var (
	// 文件内容缓存
	fileCache     = make(map[string][]byte)
	fileCacheLock sync.RWMutex
)

// 读取文件内容，带缓存功能
func readFileWithCache(filepath string) ([]byte, error) {
	fileCacheLock.RLock()
	content, exists := fileCache[filepath]
	fileCacheLock.RUnlock()
	
	if exists {
		return content, nil
	}
	
	content, err := os.ReadFile(filepath)
	if err != nil {
		return nil, err
	}
	
	fileCacheLock.Lock()
	fileCache[filepath] = content
	fileCacheLock.Unlock()
	
	return content, nil
}

// ValidateDivisionComponents 验证拆分部件是否在映射表中定义
func ValidateDivisionComponents(divTable map[string][]*types.Division, compMap map[string]string) error {
	invalidComponents := make(map[string][]string) // 部件 -> [位置信息]
	lineNumber := 0

	for char, divisions := range divTable {
		for _, division := range divisions {
			lineNumber++
			for _, component := range division.Divs {
				if _, exists := compMap[component]; !exists {
					position := fmt.Sprintf("行号: %d, 字符: %s", lineNumber, char)
					invalidComponents[component] = append(invalidComponents[component], position)
				}
			}
		}
	}

	if len(invalidComponents) > 0 {
		var errorMessages []string
		for component, positions := range invalidComponents {
			// 只显示前3个位置，避免输出过长
			displayPositions := positions
			if len(positions) > 3 {
				displayPositions = positions[:3]
			}
			errorMessages = append(errorMessages,
				fmt.Sprintf("非法部件: %s (出现位置: %s...)", component, strings.Join(displayPositions, ", ")))
		}
		return fmt.Errorf("发现非法部件:\n%s", strings.Join(errorMessages, "\n"))
	}

	return nil
}

func ReadDivisionTable(filepath string) (table map[string][]*types.Division, err error) {
	buffer, err := readFileWithCache(filepath)
	if err != nil {
		return
	}

	matcher := regexp.MustCompile("{.*?}|.")
	table = map[string][]*types.Division{}
	for _, line := range strings.Split(string(buffer), "\n") {
		if len(line) == 0 || strings.HasPrefix(line, "#") {
			continue
		}
		// 的\t[白勹丶,de_dī_dí_dì,CJK,U+7684]
		line := strings.Split(strings.TrimRight(line, "\r\n"), "\t")
		if len(line) < 2 {
			continue
		}
		// [白勹丶,de_dī_dí_dì,CJK,U+7684]
		meta := strings.Split(strings.Trim(line[1], "[]"), ",")
		if len(meta) < 4 {
			continue
		}
		div := types.Division{
			Char: line[0],
			Divs: matcher.FindAllString(meta[0], -1),
			Pin:  meta[1],
			Set:  meta[2],
			Unicode: meta[3],
		}
		if len(div.Divs) == 0 {
			continue
		}
		table[div.Char] = append(table[div.Char], &div)
	}

	return
}


func ReadCompMap(filepath string) (mappings map[string]string, err error) {
	buffer, err := readFileWithCache(filepath)
	if err != nil {
		return
	}

	mappings = map[string]string{}
	for _, line := range strings.Split(string(buffer), "\n") {
		if len(line) == 0 || strings.HasPrefix(line, "#") {
			continue
		}
		line := strings.Split(strings.TrimRight(line, "\r\n"), "\t")
		code, comp := strings.ReplaceAll(line[0], "_", "1"), line[1]
		mappings[comp] = code
	}

	return
}

func ReadCharFreq(filepath string) (freqSet map[string]int64, err error) {
	buffer, err := readFileWithCache(filepath)
	if err != nil {
		return
	}

	freqSet = map[string]int64{}
	for _, line := range strings.Split(string(buffer), "\n") {
		if len(line) == 0 || strings.HasPrefix(line, "#") {
			continue
		}
		line := strings.Split(strings.TrimRight(line, "\r\n"), "\t")
		char, freqStr := line[0], line[1]
		freq, _ := strconv.ParseFloat(freqStr, 64)
		freqSet[char] = int64(freq)
	}

	return
}




// ReadWordsFile 读取多字词文件
func ReadWordsFile(filepath string) ([]*types.WordEntry, error) {
	buffer, err := readFileWithCache(filepath)
	if err != nil {
		return nil, err
	}

	wordEntries := make([]*types.WordEntry, 0)
	for _, line := range strings.Split(string(buffer), "\n") {
		line = strings.TrimSpace(line)
		if len(line) == 0 || strings.HasPrefix(line, "#") {
			continue
		}

		// 使用制表符或空格分割
		fields := strings.Fields(line)
		if len(fields) == 0 {
			continue
		}

		word := fields[0]
		weight := ""
		if len(fields) >= 2 {
			weight = fields[1]
		}

		wordEntries = append(wordEntries, &types.WordEntry{
			Word:   word,
			Weight: weight,
		})
	}

	return wordEntries, nil
}
