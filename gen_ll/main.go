package main

import (
	"bytes"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"runtime/pprof"
	"sort"
	"strings"
	"sync"
	"time"

	"gen_ll/tools"
	"gen_ll/types"
	"gen_ll/utils"
)

type Args struct {
	Quiet      bool   `flag:"q" usage:"安静模式，不输出进度信息" default:"false"`
	Div        string `flag:"d" usage:"拆分表文件"  default:"../deploy/hao/ll_div.txt"`
	Map        string `flag:"m" usage:"映射表文件"  default:"../deploy/hao/ll_map.txt"`
	Freq       string `flag:"f" usage:"频率表文件"  default:"../deploy/hao/freq.txt"`
	Words      string `flag:"w" usage:"多字词文件"  default:"../deploy/hao/ll_words.txt"`
	Linglong   string `flag:"L" usage:"玲珑多字词文件"  default:"../deploy/hao/玲珑.txt"`
	Full       string `flag:"u" usage:"输出单字全码表文件" default:"/tmp/code_full.txt"`
	Opencc     string `flag:"o" usage:"输出拆分表文件"  default:"/tmp/div.txt"`
	Simple     string `flag:"s" usage:"输出单字简码表文件" default:"/tmp/code_simp.txt"`
	WordsFull  string `flag:"W" usage:"输出多字词全码表文件" default:"/tmp/words_full.txt"`
	WordsSimple string `flag:"S" usage:"输出多字词简码表文件" default:"/tmp/words_simp.txt"`
	LinglongFull string `flag:"F" usage:"输出玲珑多字词全码表文件" default:"/tmp/linglong_full.txt"`
	LinglongSimple string `flag:"Q" usage:"输出玲珑多字词简码表文件" default:"/tmp/linglong_simp.txt"`
	DazhuChai  string `flag:"Z" usage:"输出大竹拆文件" default:"/tmp/dazhu_chai.txt"`
	LenCodeLimit string `flag:"l" usage:"单字简码长度限制，格式：1:4,2:4,3:0,4:0" default:"1:4,2:4,3:0,4:0"`
	WordsLenCodeLimit string `flag:"wL" usage:"多字词简码长度限制，格式：1:4,2:4,3:4,4:0" default:"1:4,2:4,3:4,4:0"`
	LinglongLenCodeLimit string `flag:"ll" usage:"玲珑多字词简码长度限制，格式：1:4,2:4,3:4,4:0" default:"1:4,2:4,3:4,4:0"`
	CPUProfile string `flag:"p" usage:"CPU性能分析文件" default:"/tmp/gen_ll.prof"`
	Debug      bool   `flag:"D" usage:"调试模式" default:"false"`
	CitiPre    string `flag:"c" usage:"输出ll_citi_pre.txt文件" default:"/tmp/ll_citi_pre.txt"`
	GendaCiti  string `flag:"g" usage:"输出genda_citi.txt文件" default:"/tmp/genda_citi.txt"`
	ProcessCiti bool  `flag:"C" usage:"处理citi文件" default:"false"`
	DazhuCode   string `flag:"z" usage:"输出dazhu_code.txt文件" default:"/tmp/dazhu_code.txt"`
	PresetData string `flag:"P" usage:"输出preset_data.txt文件" default:"/tmp/lua/chars_cand/preset_data.txt"`
	RootsDict  string `flag:"R" usage:"输出LL.roots.dict.yaml文件" default:"/tmp/LL.roots.dict.yaml"`
}

var args Args

func main() {
	// 设置自定义日志格式，与Shell脚本保持一致
	log.SetFlags(0)
	log.SetOutput(new(logWriter))

	err := utils.ParseFlags(&args)
	if err != nil {
		log.Fatalf("解析参数失败: %v", err)
		return
	}

	// CPU性能分析
	if args.CPUProfile != "" {
		f, err := os.Create(args.CPUProfile)
		if err != nil {
			log.Fatalf("无法创建CPU性能分析文件: %v", err)
		}
		defer f.Close()
		if err := pprof.StartCPUProfile(f); err != nil {
			log.Fatalf("无法开始CPU性能分析: %v", err)
		}
		defer pprof.StopCPUProfile()
	}

	// 创建输出目录（如果不存在）
	ensureOutputDir(args.Full)
	ensureOutputDir(args.Opencc)
	ensureOutputDir(args.Simple)
	ensureOutputDir(args.WordsFull)
	ensureOutputDir(args.WordsSimple)
	ensureOutputDir(args.LinglongFull)
	ensureOutputDir(args.LinglongSimple)
	ensureOutputDir(args.DazhuChai)
	ensureOutputDir(args.CitiPre)
	ensureOutputDir(args.GendaCiti)
	ensureOutputDir(args.DazhuCode)
	ensureOutputDir(args.PresetData)
	ensureOutputDir(args.RootsDict)

	// 解析简码长度限制
	lenCodeLimit, err := tools.ParseLenCodeLimit(args.LenCodeLimit)
	if err != nil {
		log.Fatalf("解析单字简码长度限制失败: %v", err)
	}

	// 解析多字词简码长度限制
	wordsLenCodeLimit, err := tools.ParseLenCodeLimit(args.WordsLenCodeLimit)
	if err != nil {
		log.Fatalf("解析多字词简码长度限制失败: %v", err)
	}

	// 解析玲珑多字词简码长度限制
	linglongLenCodeLimit, err := tools.ParseLenCodeLimit(args.LinglongLenCodeLimit)
	if err != nil {
		log.Fatalf("解析玲珑多字词简码长度限制失败: %v", err)
	}

	// 记录开始时间
	startTime := utils.Now()

	if !args.Quiet {
		log.Println("开始加载表格数据...")
	}

	divTable, err := tools.ReadDivisionTable(args.Div)
	if err != nil {
		log.Fatalf("读取拆分表失败: %v", err)
	}
	if !args.Quiet {
		log.Printf("拆分表加载完成，共 %d 项\n", len(divTable))
	}

	compMap, err := tools.ReadCompMap(args.Map)
	if err != nil {
		log.Fatalf("读取映射表失败: %v", err)
	}
	if !args.Quiet {
		log.Printf("映射表加载完成，共 %d 项\n", len(compMap))
	}

	// 验证拆分部件是否在映射表中定义
	if !args.Quiet {
		log.Println("开始验证拆分部件...")
	}
	if err := tools.ValidateDivisionComponents(divTable, compMap); err != nil {
		log.Fatalf("验证失败: %v", err)
	}
	if !args.Quiet {
		log.Println("拆分部件验证通过")
	}

	freqSet, err := tools.ReadCharFreq(args.Freq)
	if err != nil {
		log.Fatalf("读取频率表失败: %v", err)
	}
	if !args.Quiet {
		log.Printf("频率表加载完成，共 %d 项\n", len(freqSet))
	}

	if !args.Quiet {
		log.Println("开始构建编码数据...")
	}

	buildStartTime := utils.Now()
	fullCodeMetaList := tools.BuildFullCodeMetaList(divTable, compMap, freqSet)
	
	if !args.Quiet {
		log.Printf("构建完成，耗时: %v\n", utils.Since(buildStartTime))
		log.Printf("fullCodeMetaList: %d\n", len(fullCodeMetaList))
		log.Println("开始写入文件...")
	}

	// 读取多字词文件并生成多字词全码和简码
	var wordCodes []*types.WordCode
	var wordSimpleCodes []*types.WordSimpleCode
	if !args.Quiet {
		log.Println("开始读取多字词文件...")
	}
	wordEntries, err := tools.ReadWordsFile(args.Words)
	if err != nil {
		log.Printf("读取多字词文件失败: %v", err)
	} else {
		if !args.Quiet {
			log.Printf("多字词文件加载完成，共 %d 项\n", len(wordEntries))
			log.Println("开始生成多字词全码...")
		}
		
		// 创建字符编码映射
		charCodeMap := tools.CreateCharCodeMap(fullCodeMetaList)
		
		// 生成多字词全码
		wordCodes = tools.BuildWordsFullCode(wordEntries, charCodeMap)
		
		if !args.Quiet {
			log.Printf("多字词全码生成完成，共 %d 项\n", len(wordCodes))
			log.Println("开始生成多字词简码...")
		}
		
		// 生成多字词简码
		wordSimpleCodes = tools.BuildWordsSimpleCode(wordCodes, wordsLenCodeLimit)
		
		if !args.Quiet {
			log.Printf("多字词简码生成完成，共 %d 项\n", len(wordSimpleCodes))
		}
	}

	// 读取玲珑多字词文件并生成玲珑多字词全码和简码
	var linglongCodes []*types.WordCode
	var linglongSimpleCodes []*types.WordSimpleCode
	if !args.Quiet {
		log.Println("开始读取玲珑多字词文件...")
	}
	linglongEntries, err := tools.ReadWordsFile(args.Linglong)
	if err != nil {
		log.Printf("读取玲珑多字词文件失败: %v", err)
	} else {
		if !args.Quiet {
			log.Printf("玲珑多字词文件加载完成，共 %d 项\n", len(linglongEntries))
			log.Println("开始生成玲珑多字词全码...")
		}
		
		// 创建字符编码映射
		charCodeMap := tools.CreateCharCodeMap(fullCodeMetaList)
		
		// 生成玲珑多字词全码
		linglongCodes = tools.BuildWordsFullCode(linglongEntries, charCodeMap)
		
		if !args.Quiet {
			log.Printf("玲珑多字词全码生成完成，共 %d 项\n", len(linglongCodes))
			log.Println("开始生成玲珑多字词简码...")
		}
		
		// 生成玲珑多字词简码（不添加占位符）
		linglongSimpleCodes = tools.BuildLinglongSimpleCode(linglongCodes, linglongLenCodeLimit)
		
		if !args.Quiet {
			log.Printf("玲珑多字词简码生成完成，共 %d 项\n", len(linglongSimpleCodes))
		}
	}

	// 生成简码表
	if !args.Quiet {
		log.Println("开始生成简码表...")
	}
	noSimplifyChars := []string{"的", "了"} // 不出简的字符列表
	simpleCodeList := tools.BuildSimpleCodeList(fullCodeMetaList, lenCodeLimit, noSimplifyChars)
	
	if !args.Quiet {
		log.Printf("简码表生成完成，共 %d 项\n", len(simpleCodeList))
		log.Println("开始写入文件...")
	}


	// 使用并行处理加速文件写入
	var wg sync.WaitGroup
	fileCount := 4 // 基础文件：FULLCHAR, SIMPLECODE, DIVISION, DAZHUCHAI
	if wordCodes != nil {
		fileCount++
	}
	if wordSimpleCodes != nil {
		fileCount++
	}
	if linglongCodes != nil {
		fileCount++
	}
	if linglongSimpleCodes != nil {
		fileCount++
	}
	wg.Add(fileCount)
	errChan := make(chan error, fileCount)

	// FULLCHAR - 全码表，格式为"汉字\t编码\t词频"
	go func() {
		defer wg.Done()
		buffer := bytes.Buffer{}
		// 全码表已经在BuildFullCodeMetaList中排序过
		for _, charMeta := range fullCodeMetaList {
			buffer.WriteString(fmt.Sprintf("%s\t%s\t%d\n", charMeta.Char, charMeta.Code, charMeta.Freq))
		}
		err := os.WriteFile(args.Full, buffer.Bytes(), 0o644)
		if err != nil {
			errChan <- fmt.Errorf("写入FULLCHAR文件错误: %w", err)
		} else if !args.Quiet {
			log.Printf("FULLCHAR文件写入完成: %s\n", args.Full)
		}
	}()

	// SIMPLECODE
	go func() {
		defer wg.Done()
		buffer := bytes.Buffer{}
		// 对简码表进行排序：编码升序，重码按词频降序
		sortedSimpleList := make([]*types.CharMeta, len(simpleCodeList))
		copy(sortedSimpleList, simpleCodeList)
		sort.Slice(sortedSimpleList, func(i, j int) bool {
			a, b := sortedSimpleList[i], sortedSimpleList[j]
			
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
		for _, charMeta := range sortedSimpleList {
			buffer.WriteString(fmt.Sprintf("%s\t%s\t%d\n", charMeta.Char, charMeta.Code, charMeta.Freq))
		}
		err := os.WriteFile(args.Simple, buffer.Bytes(), 0o644)
		if err != nil {
			errChan <- fmt.Errorf("写入SIMPLECODE文件错误: %w", err)
		} else if !args.Quiet {
			log.Printf("SIMPLECODE文件写入完成: %s\n", args.Simple)
		}
	}()

	// DIVISION
	go func() {
		defer wg.Done()
		buffer := bytes.Buffer{}
		// 创建一个副本用于排序，避免并发访问问题
		sortedList := make([]*types.CharMeta, len(fullCodeMetaList))
		copy(sortedList, fullCodeMetaList)
		sort.Slice(sortedList, func(i, j int) bool {
			return sortedList[i].Char < sortedList[j].Char
		})
		for _, charMeta := range sortedList {
			if charMeta.Division == nil {
				continue
			}
			div := strings.Join(charMeta.Division.Divs, "")
			buffer.WriteString(fmt.Sprintf("%s\t[%s·%s·%s·%s·%s]\n",
	   			charMeta.Char,
	   			div,
	   			charMeta.Full,
	   			charMeta.Division.Pin,
	   			charMeta.Division.Set,
	   			charMeta.Division.Unicode,
			))
		}
		err := os.WriteFile(args.Opencc, buffer.Bytes(), 0o644)
		if err != nil {
			errChan <- fmt.Errorf("写入DIVISION文件错误: %w", err)
		} else if !args.Quiet {
			log.Printf("DIVISION文件写入完成: %s\n", args.Opencc)
		}
	}()

	// DAZHUCHAI - 大竹拆文件，格式为两行：
	// 第一行："部件\t字"（将 Division.Divs 连接成字符串）
	// 第二行："Unicode类别〔Unicode编码〕\t字"（将第二行和第三行整合）
	go func() {
		defer wg.Done()
		buffer := bytes.Buffer{}
		// 创建一个副本用于排序，按字符Unicode顺序排序
		sortedList := make([]*types.CharMeta, len(fullCodeMetaList))
		copy(sortedList, fullCodeMetaList)
		sort.Slice(sortedList, func(i, j int) bool {
			return sortedList[i].Char < sortedList[j].Char
		})
		for _, charMeta := range sortedList {
			if charMeta.Division == nil {
				continue
			}
			// 第一行：部件\t字
			components := strings.Join(charMeta.Division.Divs, "")
			buffer.WriteString(fmt.Sprintf("%s\t%s\n", components, charMeta.Char))
			// 第二行：Unicode类别〔Unicode编码〕\t字（整合第二行和第三行）
			buffer.WriteString(fmt.Sprintf("%s〔%s〕\t%s\n", charMeta.Division.Set, charMeta.Division.Unicode, charMeta.Char))
		}
		err := os.WriteFile(args.DazhuChai, buffer.Bytes(), 0o644)
		if err != nil {
			errChan <- fmt.Errorf("写入DAZHUCHAI文件错误: %w", err)
		} else if !args.Quiet {
			log.Printf("DAZHUCHAI文件写入完成: %s\n", args.DazhuChai)
		}
	}()

	// 写入多字词全码表
	if wordCodes != nil {
		go func() {
			defer wg.Done()
			buffer := bytes.Buffer{}
			
			// 保持ll_words.txt的原始顺序，不进行排序
			for _, wordCode := range wordCodes {
				if wordCode.Weight != "" {
					buffer.WriteString(fmt.Sprintf("%s\t%s\t%s\n", wordCode.Word, wordCode.Code, wordCode.Weight))
				} else {
					buffer.WriteString(fmt.Sprintf("%s\t%s\n", wordCode.Word, wordCode.Code))
				}
			}
			err := os.WriteFile(args.WordsFull, buffer.Bytes(), 0o644)
			if err != nil {
				errChan <- fmt.Errorf("写入多字词全码表文件错误: %w", err)
			} else if !args.Quiet {
				log.Printf("多字词全码表文件写入完成: %s\n", args.WordsFull)
			}
		}()
	}


	// 写入多字词简码表
	if wordSimpleCodes != nil {
		go func() {
			defer wg.Done()
			buffer := bytes.Buffer{}
			
			// 对多字词简码进行排序
			// 先按编码升序排列，编码相同时按权重降序排列
			sortedWordSimpleCodes := make([]*types.WordSimpleCode, len(wordSimpleCodes))
			copy(sortedWordSimpleCodes, wordSimpleCodes)
			tools.SortWordSimpleCodes(sortedWordSimpleCodes)
			
			for _, wordSimpleCode := range sortedWordSimpleCodes {
				if wordSimpleCode.Weight != "" {
					buffer.WriteString(fmt.Sprintf("%s\t%s\t%s\n", wordSimpleCode.Word, wordSimpleCode.Code, wordSimpleCode.Weight))
				} else {
					buffer.WriteString(fmt.Sprintf("%s\t%s\n", wordSimpleCode.Word, wordSimpleCode.Code))
				}
			}
			err := os.WriteFile(args.WordsSimple, buffer.Bytes(), 0o644)
			if err != nil {
				errChan <- fmt.Errorf("写入多字词简码表文件错误: %w", err)
			} else if !args.Quiet {
				log.Printf("多字词简码表文件写入完成: %s\n", args.WordsSimple)
			}
		}()
	}

	// 写入玲珑多字词全码表
	if linglongCodes != nil {
		go func() {
			defer wg.Done()
			buffer := bytes.Buffer{}
			
			// 保持玲珑.txt的原始顺序，不进行排序
			for _, wordCode := range linglongCodes {
				if wordCode.Weight != "" {
					buffer.WriteString(fmt.Sprintf("%s\t%s\t%s\n", wordCode.Word, wordCode.Code, wordCode.Weight))
				} else {
					buffer.WriteString(fmt.Sprintf("%s\t%s\n", wordCode.Word, wordCode.Code))
				}
			}
			err := os.WriteFile(args.LinglongFull, buffer.Bytes(), 0o644)
			if err != nil {
				errChan <- fmt.Errorf("写入玲珑多字词全码表文件错误: %w", err)
			} else if !args.Quiet {
				log.Printf("玲珑多字词全码表文件写入完成: %s\n", args.LinglongFull)
			}
		}()
	}

	// 写入玲珑多字词简码表
	if linglongSimpleCodes != nil {
		go func() {
			defer wg.Done()
			buffer := bytes.Buffer{}
			
			// 对玲珑多字词简码进行排序
			// 先按编码升序排列，编码相同时按权重降序排列
			sortedLinglongSimpleCodes := make([]*types.WordSimpleCode, len(linglongSimpleCodes))
			copy(sortedLinglongSimpleCodes, linglongSimpleCodes)
			tools.SortWordSimpleCodes(sortedLinglongSimpleCodes)
			
			for _, wordSimpleCode := range sortedLinglongSimpleCodes {
				if wordSimpleCode.Weight != "" {
					buffer.WriteString(fmt.Sprintf("%s\t%s\t%s\n", wordSimpleCode.Word, wordSimpleCode.Code, wordSimpleCode.Weight))
				} else {
					buffer.WriteString(fmt.Sprintf("%s\t%s\n", wordSimpleCode.Word, wordSimpleCode.Code))
				}
			}
			err := os.WriteFile(args.LinglongSimple, buffer.Bytes(), 0o644)
			if err != nil {
				errChan <- fmt.Errorf("写入玲珑多字词简码表文件错误: %w", err)
			} else if !args.Quiet {
				log.Printf("玲珑多字词简码表文件写入完成: %s\n", args.LinglongSimple)
			}
		}()
	}

	// 等待所有写入操作完成
	wg.Wait()
	close(errChan)

	// 检查是否有错误
	for err := range errChan {
		log.Fatalln(err)
	}

	// 输出处理时间
	if !args.Quiet {
		log.Printf("处理完成，总耗时: %v\n", utils.Since(startTime))
	}

	// 处理跟打词提
	if args.ProcessCiti {
		log.Println("开始处理跟打词提文件...")
		// 使用玲珑词库的词语部分
		err := tools.ProcessCitiFilesWithLinglong(args.Simple, args.Full, args.LinglongSimple, args.LinglongFull, args.CitiPre, args.GendaCiti)
		if err != nil {
			log.Printf("处理跟打词提文件失败: %v", err)
		} else {
			log.Println("跟打词提文件处理完成")
			
			// 生成大竹词提
			log.Println("开始生成大竹词提...")
			err := tools.CreateDazhuCode(args.GendaCiti, args.DazhuCode, 30)
			if err != nil {
				log.Printf("生成大竹词提失败: %v", err)
			} else {
				log.Println("大竹词提生成完成")
			}
		}
	}

	// 新增功能：将生成的文件追加到输出目录的字典文件
	if !args.Quiet {
		log.Println("开始将生成的文件追加到字典文件...")
	}
	
	// 获取输出目录
	outputDir := filepath.Dir(args.Full)
	
	// 将div_ll.txt追加到LL_chaifen.dict.yaml
	if !args.Quiet {
		log.Println("将div_ll.txt追加到LL_chaifen.dict.yaml...")
	}
	err = tools.AppendToDictFile(args.Opencc, filepath.Join(outputDir, "LL_chaifen.dict.yaml"), false, false)
	if err != nil {
		log.Printf("追加div_ll.txt到LL_chaifen.dict.yaml失败: %v", err)
	} else if !args.Quiet {
		log.Println("div_ll.txt追加到LL_chaifen.dict.yaml完成")
	}
	
	// 将code_chars_simp.txt追加到LL.chars.quick.dict.yaml（需要排序和删除词频）
	if !args.Quiet {
		log.Println("将code_chars_simp.txt追加到LL.chars.quick.dict.yaml...")
	}
	err = tools.AppendToDictFile(args.Simple, filepath.Join(outputDir, "LL.chars.quick.dict.yaml"), true, true)
	if err != nil {
		log.Printf("追加code_chars_simp.txt到LL.chars.quick.dict.yaml失败: %v", err)
	} else if !args.Quiet {
		log.Println("code_chars_simp.txt追加到LL.chars.quick.dict.yaml完成")
	}
	
	// 将code_chars_full.txt追加到LL.chars.full.dict.yaml（需要排序和删除词频）
	if !args.Quiet {
		log.Println("将code_chars_full.txt追加到LL.chars.full.dict.yaml...")
	}
	err = tools.AppendToDictFile(args.Full, filepath.Join(outputDir, "LL.chars.full.dict.yaml"), true, true)
	if err != nil {
		log.Printf("追加code_chars_full.txt到LL.chars.full.dict.yaml失败: %v", err)
	} else if !args.Quiet {
		log.Println("code_chars_full.txt追加到LL.chars.full.dict.yaml完成")
	}
	
	// 将code_words_simp.txt追加到LL.words.quick.dict.yaml（需要排序和删除词频）
	if !args.Quiet {
		log.Println("将code_words_simp.txt追加到LL.words.quick.dict.yaml...")
	}
	err = tools.AppendToDictFile(args.WordsSimple, filepath.Join(outputDir, "LL.words.quick.dict.yaml"), true, true)
	if err != nil {
		log.Printf("追加code_words_simp.txt到LL.words.quick.dict.yaml失败: %v", err)
	} else if !args.Quiet {
		log.Println("code_words_simp.txt追加到LL.words.quick.dict.yaml完成")
	}
	
	// 将code_words_full.txt追加到LL.words.full.dict.yaml（需要排序和删除词频）
	if !args.Quiet {
		log.Println("将code_words_full.txt追加到LL.words.full.dict.yaml...")
	}
	err = tools.AppendToDictFile(args.WordsFull, filepath.Join(outputDir, "LL.words.full.dict.yaml"), true, true)
	if err != nil {
		log.Printf("追加code_words_full.txt到LL.words.full.dict.yaml失败: %v", err)
	} else if !args.Quiet {
		log.Println("code_words_full.txt追加到LL.words.full.dict.yaml完成")
	}
	
	// 将linglong_full.txt追加到LL_linglong.full.dict.yaml（需要排序和删除词频）
	if !args.Quiet {
		log.Println("将linglong_full.txt追加到LL_linglong.full.dict.yaml...")
	}
	err = tools.AppendToDictFile(args.LinglongFull, filepath.Join(outputDir, "LL_linglong.full.dict.yaml"), true, true)
	if err != nil {
		log.Printf("追加linglong_full.txt到LL_linglong.full.dict.yaml失败: %v", err)
	} else if !args.Quiet {
		log.Println("linglong_full.txt追加到LL_linglong.full.dict.yaml完成")
	}
	
	// 将linglong_simp.txt追加到LL_linglong.quick.dict.yaml（需要排序和删除词频）
	if !args.Quiet {
		log.Println("将linglong_simp.txt追加到LL_linglong.quick.dict.yaml...")
	}
	err = tools.AppendToDictFile(args.LinglongSimple, filepath.Join(outputDir, "LL_linglong.quick.dict.yaml"), true, true)
	if err != nil {
		log.Printf("追加linglong_simp.txt到LL_linglong.quick.dict.yaml失败: %v", err)
	} else if !args.Quiet {
		log.Println("linglong_simp.txt追加到LL_linglong.quick.dict.yaml完成")
	}
	
	// 生成字根码表并追加到LL.roots.dict.yaml
	if !args.Quiet {
		log.Println("开始生成字根码表...")
	}
	err = tools.GenerateRootsDict(args.Map, args.RootsDict)
	if err != nil {
		log.Printf("生成字根码表失败: %v", err)
	} else if !args.Quiet {
		log.Printf("字根码表生成完成: %s\n", args.RootsDict)
	}

	// 在追加完所有字典文件后生成 preset_data.txt
	if !args.Quiet {
		log.Println("开始生成 preset_data.txt...")
	}
	presetDataLines, err := tools.BuildPresetData(simpleCodeList, fullCodeMetaList)
	if err != nil {
		log.Printf("生成 preset_data.txt 失败: %v", err)
	} else if !args.Quiet {
		log.Printf("preset_data.txt 生成完成，共 %d 项\n", len(presetDataLines))
	}

	// 写入 preset_data.txt
	if !args.Quiet {
		log.Println("开始写入 preset_data.txt...")
	}
	err = os.WriteFile(args.PresetData, []byte(strings.Join(presetDataLines, "\n")), 0o644)
	if err != nil {
		log.Printf("写入 preset_data.txt 失败: %v", err)
	} else if !args.Quiet {
		log.Printf("preset_data.txt 写入完成: %s\n", args.PresetData)
	}
}

// 确保输出目录存在
func ensureOutputDir(path string) {
	dir := filepath.Dir(path)
	if dir != "" && dir != "." {
		if err := os.MkdirAll(dir, 0755); err != nil {
			log.Fatalf("无法创建目录 %s: %v", dir, err)
		}
	}
}

// logWriter 自定义日志写入器，格式与Shell脚本保持一致
type logWriter struct{}

func (writer logWriter) Write(bytes []byte) (int, error) {
	timestamp := time.Now().Format("2006-01-02 15:04:05")
	return fmt.Printf("[%s] %s", timestamp, string(bytes))
}
