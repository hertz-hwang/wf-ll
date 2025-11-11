#!/bin/bash

# 离乱输入法部署脚本
# 用途：生成离乱输入法的 RIME 方案并打包发布
# 作者：荒
# 最后更新：$(date +%Y-%m-%d)

set -e  # 遇到错误立即退出
set -u  # 使用未定义的变量时报错

# 日志函数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >&2
}

error() {
    log "错误: $1" >&2
    exit 1
}

# 检测操作系统类型
OS_TYPE=$(uname)

# 初始化环境变量和工作目录
#source ~/.zshrc

cd "$(dirname $0)" || error "无法切换到脚本目录"
WD="$(pwd)"
SCHEMAS="../schemas"
REF_NAME="${REF_NAME:-v$(date +%Y%m%d%H%M)}"

# 创建本地临时目录
create_ramdisk() {
    RAMDISK="./tmp"
    
    # 清理并重新创建临时目录
    rm -rf "${RAMDISK}"
    mkdir -p "${RAMDISK}" || error "无法创建临时目录"
    
    log "成功创建本地临时目录: ${RAMDISK}"
}

# 清理和准备目录
rm -rf "${SCHEMAS}/ll/build" "${SCHEMAS}/releases" "${SCHEMAS}/ll/lua/chars_cand.userdb"
create_ramdisk
mkdir -p "${SCHEMAS}/releases"

# 生成输入方案
gen_schema() {
    local NAME="$1"
    local DESC="${2:-${NAME}}"
    
    if [ -z "${NAME}" ]; then
        error "方案名称不能为空"
    fi
    
    log "开始生成方案: ${NAME}"
    
    local LL="${RAMDISK}"
    # 设置环境变量
    export SCHEMAS_DIR="${LL}"
    export ASSETS_DIR="${LL}"
    mkdir -p "${LL}" || error "无法创建必要目录"

    # 复制基础文件到临时目录
    log "复制基础文件到临时目录..."
    cp ../template/*.txt "${LL}" || error "复制自定义码表文件失败"
    cp ../template/*.yaml "${LL}" || error "复制模板文件失败"
    cp -r ../template/lua "${LL}/lua" || error "复制 Lua 脚本失败"
    cp -r ../template/build_template "${LL}/build_template" || error "复制 fixed_user 伪码表失败"
    #cp -r ../template/opencc "${LL}/opencc" || error "复制 OpenCC 配置失败"
    # 使用自定义配置覆盖默认值
    if [ -d "${NAME}" ]; then
        log "应用自定义配置..."
        cp -r "${NAME}"/*.txt "${LL}"
    fi

    # 确保玲珑.txt文件存在
    if [ ! -f "${LL}/玲珑.txt" ]; then
        log "警告: 玲珑.txt文件不存在，跳过玲珑多字词处理"
    fi
    
    # -l  一字词简码长度限制
    # -ll 玲珑词简码长度限制
    # -wL 多字词简码长度限制
    log "生成${NAME}码表..."
    ./gen_ll -q \
        -d "${LL}/ll_div.txt" \
        -m "${LL}/ll_map.txt" \
        -w "${LL}/ll_words.txt" \
        -L "${LL}/玲珑.txt" \
        -f "${LL}/freq.txt" \
        -l "1:4,2:4,3:0,4:0" \
        -ll "1:4,2:4,3:4,4:0" \
        -wL "1:0,2:10,3:10,4:0" \
        -u "${LL}/code_chars_full.txt" \
        -s "${LL}/code_chars_simp.txt" \
        -W "${LL}/code_words_full.txt" \
        -S "${LL}/code_words_simp.txt" \
        -F "${LL}/linglong_full.txt" \
        -Q "${LL}/linglong_simp.txt" \
        -o "${LL}/div_ll.txt" \
        -Z "${LL}/大竹_chai.txt" \
        -C \
        -c "${LL}/ll_citi_pre.txt" \
        -g "${LL}/跟打词提.txt" \
        -gn "${LL}/跟打词提_无简词.txt" \
        -z "${LL}/大竹_code.txt" \
        -zn "${LL}/大竹_code_无简词.txt" \
        -P "${LL}/lua/chars_cand/preset_data.txt" \
        -R "${LL}/LL.roots.dict.yaml" \
        || error "生成${NAME}码表失败"

    log "准备生成Rime方案..."
    rsync -a --exclude='/code_*.txt' \
        --exclude='/玲珑.txt' \
        --exclude='/大竹_*.txt' \
        --exclude='/跟打词提.txt' \
        --exclude='/linglong_*.txt' \
        --exclude='/div_ll.txt' \
        --exclude='/freq.txt' \
        --exclude='/ll_citi_pre.txt' \
        --exclude='/ll_div.txt' \
        --exclude='/ll_map.txt' \
        --exclude='/ll_words.txt' \
        "${LL}/" "${SCHEMAS}/ll/" || error "复制文件失败"

    # 打包发布
    log "打包发布文件..."
    (cd "${SCHEMAS}" || error "无法切换到发布目录"
        tar -cf - \
            --exclude="build" \
            --exclude="*userdb" \
            --exclude="sync" \
            --exclude="*.custom.yaml" \
            --exclude="installation.yaml" \
            --exclude="user.yaml" \
            --exclude="squirrel.yaml" \
            --exclude="weasel.yaml" \
            --exclude="LL.txt" \
            --exclude="大竹*.txt" \
            --exclude="跟打词提.txt" \
            --exclude="speed_stats.conf" \
            "./ll" | \
            zstd -9 -T0 -c \
            > "releases/${NAME}-${REF_NAME}.tar.zst" \
            || error "打包失败"
        log "打包仓输入法包..."
        (cd "./ll" && zip -9 -r -q "../releases/${NAME}-${REF_NAME}.zip" . \
            -x "build/**" \
            -x "*userdb*" \
            -x "sync/**" \
            -x "*.custom.yaml" \
            -x "installation.yaml" \
            -x "user.yaml" \
            -x "squirrel.yaml" \
            -x "weasel.yaml" \
            -x "LL.txt" \
            -x "大竹*.txt" \
            -x "跟打词提.txt" \
            -x "speed_stats.conf") || error "仓输入法包打包失败"
    )
    log "方案 ${NAME} 生成完成"
}

# 主程序
NAME="离乱"
log "开始构建${NAME}方案..."
gen_schema "${NAME}" || error "生成${NAME}方案失败"
log "${NAME}方案构建完成"
