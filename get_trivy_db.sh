#!/bin/bash

# Trivy 数据库管理脚本
# 用途：外网下载数据库，内网同步安装

set -e

# 配置变量
TRIVY_DB_REPO="ghcr.m.daocloud.io/aquasecurity/trivy-db"
TRIVY_JAVA_DB_REPO="ghcr.m.daocloud.io/aquasecurity/trivy-java-db"
TRIVY_CACHE_DIR="${HOME}/.cache/trivy"
TRIVY_DB_DIR="${TRIVY_CACHE_DIR}/db"
TRIVY_JAVA_DB_DIR="${TRIVY_CACHE_DIR}/java-db"
BACKUP_DIR="./trivy-db-backup"
DB_ARCHIVE="trivy-database-$(date +%Y%m%d).tar.gz"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
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

# 显示帮助信息
show_help() {
    cat << EOF
Trivy 数据库管理脚本

用法: $0 [选项]

选项:
    download    下载最新的 Trivy 数据库并打包（外网环境使用）
    update      从当前目录的压缩包更新 Trivy 数据库（内网环境使用）
    status      显示当前数据库状态
    clean       清理旧的数据库文件
    -h, --help  显示此帮助信息

示例:
    # 外网环境下载数据库
    $0 download
    
    # 内网环境更新数据库
    $0 update
    
    # 查看数据库状态
    $0 status

EOF
}

# 检查 trivy 是否安装
check_trivy() {
    if ! command -v trivy &> /dev/null; then
        log_error "Trivy 未安装，请先安装 Trivy"
        exit 1
    fi
}

# 创建必要的目录
create_directories() {
    mkdir -p "$TRIVY_DB_DIR"
    mkdir -p "$TRIVY_JAVA_DB_DIR"
    mkdir -p "$BACKUP_DIR"
}

# 下载数据库
download_database() {
    log_info "开始下载 Trivy 数据库..."
    
    # 检查网络连接
    if ! ping -c 1 google.com &> /dev/null; then
        log_warning "网络连接可能有问题，尝试继续..."
    fi
    
    # 创建目录
    create_directories
    
    # 下载漏洞数据库
    log_info "下载漏洞数据库..."
    trivy image --download-db-only --db-repository "$TRIVY_DB_REPO" --cache-dir "$TRIVY_CACHE_DIR"
    
    # 下载 Java 数据库
    log_info "下载 Java 数据库..."
    trivy image --download-java-db-only --db-repository "$TRIVY_JAVA_DB_REPO" --cache-dir "$TRIVY_CACHE_DIR"
    
    # 备份当前数据库
    backup_current_database
    
    # 打包数据库
    package_database
    
    log_success "数据库下载和打包完成！"
    log_info "压缩包位置: $(pwd)/$DB_ARCHIVE"
}

# 备份当前数据库
backup_current_database() {
    if [[ -d "$TRIVY_DB_DIR" ]] && [[ -n "$(ls -A "$TRIVY_DB_DIR" 2>/dev/null)" ]]; then
        log_info "备份当前数据库..."
        local backup_name="trivy-db-backup-$(date +%Y%m%d-%H%M%S)"
        cp -r "$TRIVY_DB_DIR" "$BACKUP_DIR/$backup_name"
        log_success "数据库已备份到: $BACKUP_DIR/$backup_name"
    fi
}

# 打包数据库
package_database() {
    log_info "打包数据库文件..."
    
    # 检查数据库文件是否存在
    if [[ ! -d "$TRIVY_CACHE_DIR" ]] || [[ -z "$(ls -A "$TRIVY_CACHE_DIR" 2>/dev/null)" ]]; then
        log_error "数据库目录为空或不存在"
        exit 1
    fi
    
    # 创建压缩包
    tar -czf "$DB_ARCHIVE" -C "$HOME/.cache" trivy/
    
    # 验证压缩包
    if [[ -f "$DB_ARCHIVE" ]]; then
        local size=$(du -h "$DB_ARCHIVE" | cut -f1)
        log_success "数据库打包完成，大小: $size"
    else
        log_error "打包失败"
        exit 1
    fi
}

# 更新数据库
update_database() {
    log_info "开始更新 Trivy 数据库..."
    
    # 查找压缩包
    local archive_file=""
    if [[ -f "$DB_ARCHIVE" ]]; then
        archive_file="$DB_ARCHIVE"
    else
        # 查找当前目录下的 trivy 数据库压缩包
        archive_file=$(find . -name "trivy-database-*.tar.gz" -type f | head -n 1)
    fi
    
    if [[ -z "$archive_file" ]]; then
        log_error "未找到数据库压缩包"
        log_info "请确保压缩包在当前目录下，文件名格式: trivy-database-YYYYMMDD.tar.gz"
        exit 1
    fi
    
    log_info "找到数据库压缩包: $archive_file"
    
    # 备份当前数据库
    backup_current_database
    
    # 创建目录
    create_directories
    
    # 解压数据库
    log_info "解压数据库文件..."
    tar -xzf "$archive_file" -C "$HOME/.cache/"
    
    # 验证解压结果
    if [[ -d "$TRIVY_DB_DIR" ]] && [[ -n "$(ls -A "$TRIVY_DB_DIR" 2>/dev/null)" ]]; then
        log_success "数据库更新完成！"
        show_database_status
    else
        log_error "数据库更新失败"
        exit 1
    fi
}

# 显示数据库状态
show_database_status() {
    log_info "Trivy 数据库状态:"
    
    if [[ -d "$TRIVY_DB_DIR" ]]; then
        local db_files=$(find "$TRIVY_DB_DIR" -name "*.db" | wc -l)
        local db_size=$(du -sh "$TRIVY_DB_DIR" 2>/dev/null | cut -f1 || echo "未知")
        local db_date=$(stat -c %y "$TRIVY_DB_DIR" 2>/dev/null | cut -d' ' -f1 || echo "未知")
        
        echo "  漏洞数据库目录: $TRIVY_DB_DIR"
        echo "  数据库文件数量: $db_files"
        echo "  数据库大小: $db_size"
        echo "  最后更新时间: $db_date"
    else
        echo "  漏洞数据库: 未安装"
    fi
    
    if [[ -d "$TRIVY_JAVA_DB_DIR" ]]; then
        local java_db_size=$(du -sh "$TRIVY_JAVA_DB_DIR" 2>/dev/null | cut -f1 || echo "未知")
        local java_db_date=$(stat -c %y "$TRIVY_JAVA_DB_DIR" 2>/dev/null | cut -d' ' -f1 || echo "未知")
        
        echo "  Java数据库目录: $TRIVY_JAVA_DB_DIR"
        echo "  Java数据库大小: $java_db_size"
        echo "  最后更新时间: $java_db_date"
    else
        echo "  Java数据库: 未安装"
    fi
    
    # 显示备份信息
    if [[ -d "$BACKUP_DIR" ]] && [[ -n "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]]; then
        local backup_count=$(ls -1 "$BACKUP_DIR" | wc -l)
        echo "  备份数量: $backup_count"
    fi
}

# 清理旧文件
clean_old_files() {
    log_info "清理旧的数据库文件..."
    
    # 清理超过30天的备份
    if [[ -d "$BACKUP_DIR" ]]; then
        find "$BACKUP_DIR" -type d -name "trivy-db-backup-*" -mtime +30 -exec rm -rf {} \; 2>/dev/null || true
        log_success "已清理30天前的备份文件"
    fi
    
    # 清理旧的压缩包（保留最新的3个）
    local old_archives=$(ls -t trivy-database-*.tar.gz 2>/dev/null | tail -n +4)
    if [[ -n "$old_archives" ]]; then
        echo "$old_archives" | xargs rm -f
        log_success "已清理旧的数据库压缩包"
    fi
}

# 主函数
main() {
    case "${1:-}" in
        download)
            check_trivy
            download_database
            ;;
        update)
            check_trivy
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
            log_error "请指定操作类型"
            show_help
            exit 1
            ;;
        *)
            log_error "未知选项: $1"
            show_help
            exit 1
            ;;
    esac
}

# 执行主函数
main "$@"
