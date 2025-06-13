#!/bin/bash

# 扫描器数据库管理脚本
# 用途：为 Trivy 和 Grype 在外网下载数据库，内网同步安装

set -e

# --- 全局配置 ---

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 备份目录和日期格式的存档名称将在选择工具后定义
BACKUP_DIR_BASE="./db-backups"
DB_ARCHIVE=""
BACKUP_DIR=""

# --- 工具特定配置 (将在主逻辑中填充) ---
TOOL_NAME=""
TOOL_CMD=""
CACHE_DIR=""
DB_DIR=""
# Trivy 特有的变量
JAVA_DB_DIR=""
TRIVY_DB_REPO="ghcr.m.daocloud.io/aquasecurity/trivy-db"
TRIVY_JAVA_DB_REPO="ghcr.m.daocloud.io/aquasecurity/trivy-java-db"


# --- 日志函数 (无改动) ---
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# --- 帮助信息 (已更新) ---
show_help() {
    cat << EOF
扫描器数据库管理脚本 (Trivy & Grype)

用法: $0 <trivy|grype> [选项]

工具:
    trivy       操作 Trivy 数据库
    grype       操作 Grype 数据库

选项:
    download    下载最新的数据库并打包（外网环境使用）
    update      从当前目录的压缩包更新数据库（内网环境使用）
    status      显示当前数据库状态
    clean       清理旧的数据库文件和备份
    -h, --help  显示此帮助信息

示例:
    # 外网环境下载 Trivy 数据库
    $0 trivy download
    
    # 内网环境更新 Trivy 数据库
    $0 trivy update
    
    # 查看 Grype 数据库状态
    $0 grype status

    # 清理旧的 Grype 压缩包和备份
    $0 grype clean
EOF
}

# --- 泛化后的核心函数 ---

# 检查工具是否安装
check_tool_installed() {
    if ! command -v "$TOOL_CMD" &> /dev/null; then
        log_error "${TOOL_NAME} 未安装，请先安装 ${TOOL_NAME}"
        exit 1
    fi
}

# 创建必要的目录
create_directories() {
    mkdir -p "$DB_DIR"
    mkdir -p "$BACKUP_DIR"
    if [[ "$TOOL_NAME" == "Trivy" ]]; then
        mkdir -p "$JAVA_DB_DIR"
    fi
}

# 下载数据库 (已适配不同工具)
download_database() {
    log_info "开始为 ${TOOL_NAME} 下载数据库..."
    
    # 检查网络连接
    if ! ping -c 1 google.com &> /dev/null; then
        log_warning "网络连接可能有问题，尝试继续..."
    fi
    
    create_directories
    
    # 根据工具执行不同的下载命令
    if [[ "$TOOL_NAME" == "Trivy" ]]; then
        log_info "下载 Trivy 漏洞数据库..."
        trivy image --download-db-only --db-repository "$TRIVY_DB_REPO" --cache-dir "$CACHE_DIR"
        
        log_info "下载 Trivy Java 数据库..."
        trivy image --download-java-db-only --db-repository "$TRIVY_JAVA_DB_REPO" --cache-dir "$CACHE_DIR"
    elif [[ "$TOOL_NAME" == "Grype" ]]; then
        log_info "下载 Grype 漏洞数据库..."
        # Grype 会自动将数据库下载到其缓存目录
        grype db update
    fi
    
    # 备份和打包是通用流程
    backup_current_database
    package_database
    
    log_success "${TOOL_NAME} 数据库下载和打包完成！"
    log_info "压缩包位置: $(pwd)/$DB_ARCHIVE"
}

# 备份当前数据库 (已泛化)
backup_current_database() {
    if [[ -d "$DB_DIR" ]] && [[ -n "$(ls -A "$DB_DIR" 2>/dev/null)" ]]; then
        log_info "备份当前 ${TOOL_NAME} 数据库..."
        local backup_name="${TOOL_NAME,,}-db-backup-$(date +%Y%m%d-%H%M%S)"
        # 备份整个缓存目录以确保所有相关文件都被保存
        cp -r "$CACHE_DIR" "$BACKUP_DIR/$backup_name"
        log_success "数据库已备份到: $BACKUP_DIR/$backup_name"
    fi
}

# 打包数据库 (已泛化)
package_database() {
    log_info "打包 ${TOOL_NAME} 数据库文件..."
    
    if [[ ! -d "$CACHE_DIR" ]] || [[ -z "$(ls -A "$CACHE_DIR" 2>/dev/null)" ]]; then
        log_error "${TOOL_NAME} 数据库目录 ($CACHE_DIR) 为空或不存在"
        exit 1
    fi
    
    # 从 HOME/.cache 目录开始打包，以保持正确的目录结构
    local cache_parent_dir=$(dirname "$CACHE_DIR")
    local cache_base_name=$(basename "$CACHE_DIR")
    tar -czf "$DB_ARCHIVE" -C "$cache_parent_dir" "$cache_base_name/"
    
    if [[ -f "$DB_ARCHIVE" ]]; then
        local size=$(du -h "$DB_ARCHIVE" | cut -f1)
        log_success "${TOOL_NAME} 数据库打包完成，大小: $size"
    else
        log_error "打包失败"
        exit 1
    fi
}

# 更新数据库 (已泛化)
update_database() {
    log_info "开始更新 ${TOOL_NAME} 数据库..."
    
    local archive_file=""
    if [[ -f "$DB_ARCHIVE" ]]; then
        archive_file="$DB_ARCHIVE"
    else
        # 查找当前目录下的对应工具的数据库压缩包
        archive_file=$(find . -maxdepth 1 -name "${TOOL_NAME,,}-database-*.tar.gz" -type f | sort -r | head -n 1)
    fi
    
    if [[ -z "$archive_file" ]]; then
        log_error "未找到 ${TOOL_NAME} 数据库压缩包"
        log_info "请确保压缩包在当前目录下，文件名格式: ${TOOL_NAME,,}-database-YYYYMMDD.tar.gz"
        exit 1
    fi
    
    log_info "找到数据库压缩包: $archive_file"
    
    backup_current_database
    create_directories
    
    log_info "解压数据库文件..."
    # 解压到 HOME/.cache 目录，tar包内包含了 trivy/ 或 grype/ 目录
    local cache_parent_dir=$(dirname "$CACHE_DIR")
    # 解压前先清空旧目录，避免文件残留问题
    log_info "正在清空旧的缓存目录: ${CACHE_DIR}"
    rm -rf "${CACHE_DIR}"
    tar -xzf "$archive_file" -C "$cache_parent_dir"
    
    if [[ -d "$DB_DIR" ]] && [[ -n "$(ls -A "$DB_DIR" 2>/dev/null)" ]]; then
        log_success "${TOOL_NAME} 数据库更新完成！"
        show_database_status
    else
        log_error "${TOOL_NAME} 数据库更新失败"
        exit 1
    fi
}

# 显示数据库状态 (已适配不同工具)
show_database_status() {
    log_info "${TOOL_NAME} 数据库状态:"
    
    if [[ -d "$DB_DIR" ]]; then
        local db_files=$(find "$DB_DIR" -type f | wc -l)
        local db_size=$(du -sh "$CACHE_DIR" 2>/dev/null | cut -f1 || echo "未知")
        # 使用 cache 目录的修改时间更准确
        local db_date=$(stat -c %y "$CACHE_DIR" 2>/dev/null | cut -d' ' -f1 || echo "未知")
        
        echo "  缓存目录: $CACHE_DIR"
        echo "  数据库文件数量 (粗略): $db_files"
        echo "  总大小: $db_size"
        echo "  最后更新时间: $db_date"
        
        # Trivy 特有的 Java DB 信息
        if [[ "$TOOL_NAME" == "Trivy" && -d "$JAVA_DB_DIR" ]]; then
            local java_db_size=$(du -sh "$JAVA_DB_DIR" 2>/dev/null | cut -f1 || echo "未知")
            echo "  Java数据库大小: $java_db_size"
        fi
    else
        echo "  ${TOOL_NAME} 数据库: 未安装"
    fi
    
    if [[ -d "$BACKUP_DIR" ]] && [[ -n "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]]; then
        local backup_count=$(ls -1 "$BACKUP_DIR" | wc -l)
        echo "  备份数量: $backup_count"
    fi
}

# 清理旧文件 (已泛化)
clean_old_files() {
    log_info "清理 ${TOOL_NAME} 的旧文件..."
    
    # 清理超过30天的备份
    if [[ -d "$BACKUP_DIR" ]]; then
        find "$BACKUP_DIR" -type d -name "${TOOL_NAME,,}-db-backup-*" -mtime +30 -exec rm -rf {} \; 2>/dev/null || true
        log_success "已清理30天前的 ${TOOL_NAME} 备份文件"
    fi
    
    # 清理旧的压缩包（保留最新的3个）
    local old_archives=$(ls -t ${TOOL_NAME,,}-database-*.tar.gz 2>/dev/null | tail -n +4)
    if [[ -n "$old_archives" ]]; then
        echo "$old_archives" | xargs rm -f
        log_success "已清理旧的 ${TOOL_NAME} 数据库压缩包"
    fi
}

# --- 主函数 (已重构) ---
main() {
    TOOL_CHOICE="${1:-}"
    ACTION="${2:-}"

    # 根据第一个参数设置工具特定的变量
    case "$TOOL_CHOICE" in
        trivy)
            TOOL_NAME="Trivy"
            TOOL_CMD="trivy"
            CACHE_DIR="${HOME}/.cache/trivy"
            DB_DIR="${CACHE_DIR}/db"
            JAVA_DB_DIR="${CACHE_DIR}/java-db"
            ;;
        grype)
            TOOL_NAME="Grype"
            TOOL_CMD="grype"
            CACHE_DIR="${HOME}/.cache/grype"
            DB_DIR="${CACHE_DIR}/db" # Grype 的主数据库也在此
            ;;
        -h|--help|help|"")
            show_help
            exit 0
            ;;
        *)
            log_error "未知的工具: $TOOL_CHOICE"
            show_help
            exit 1
            ;;
    esac

    # 为选定的工具设置动态文件名和目录
    DB_ARCHIVE="${TOOL_NAME,,}-database-$(date +%Y%m%d).tar.gz"
    BACKUP_DIR="${BACKUP_DIR_BASE}/${TOOL_NAME,,}"

    # 检查工具是否已安装 (除了 help 以外的所有操作都需要)
    if [[ "$ACTION" != "-h" && "$ACTION" != "--help" && "$ACTION" != "help" ]]; then
       check_tool_installed
    fi

    # 根据第二个参数执行操作
    case "$ACTION" in
        download)
            download_database
            ;;
        update)
            update_database
            ;;
        status)
            show_database_status
            ;;
        clean)
            clean_old_files
            ;;
        -h|--help|help)
            show_help
            ;;
        "")
            log_error "请为工具 '${TOOL_NAME}' 指定一个操作"
            show_help
            exit 1
            ;;
        *)
            log_error "未知选项: $ACTION"
            show_help
            exit 1
            ;;
    esac
}

# 执行主函数，传递所有命令行参数
main "$@"
