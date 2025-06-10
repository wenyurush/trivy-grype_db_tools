Trivy 数据库管理脚本

用法: get_trivy_db.sh [选项]

选项:
    download    下载最新的 Trivy 数据库并打包（外网环境使用）
    update      从当前目录的压缩包更新 Trivy 数据库（内网环境使用）
    status      显示当前数据库状态
    clean       清理旧的数据库文件
    -h, --help  显示此帮助信息

示例:
    # 外网环境下载数据库
    get_trivy_db.sh download
    
    # 内网环境更新数据库
    get_trivy_db.sh update
    
    # 查看数据库状态
    get_trivy_db.sh status
