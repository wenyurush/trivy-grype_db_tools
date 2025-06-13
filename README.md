# 扫描器数据库离线管理脚本 (Trivy & Grype)

这是一个强大的 Bash 脚本，用于管理 **Trivy** 和 **Grype** 的漏洞数据库，特别为在**（air-gapped）环境**中部署和更新扫描器而设计。

你可以在一台可以访问互联网的机器上下载最新的数据库，然后将生成的压缩包传输到内部网络，用它来更新离线环境中的扫描器数据库。

## ✨ 功能特性

-   **双工具支持**: 同时支持 `Trivy` 和 `Grype` 两种主流扫描器。
-   **一键下载与打包**: 自动从官方源（Trivy 使用了 `ghcr.m.daocloud.io` 加速镜像）下载最新的漏洞数据库，并将其打包成一个带时间戳的 `.tar.gz` 压缩文件。
-   **轻松离线更新**: 在离线机器上，只需一条命令即可从压缩包解压并安装数据库。
-   **自动备份**: 在更新数据库之前，脚本会自动备份当前的数据库，防止更新失败导致数据丢失。
-   **状态检查**: 随时查看本地数据库的状态，包括大小和最后更新时间。
-   **智能清理**: 自动清理过时（超过30天）的备份和旧的数据库压缩包（仅保留最新的3个），节省磁盘空间。
-   **用户友好**: 提供清晰的、带颜色高亮的日志输出和详细的帮助信息。

## ⚙️ 先决条件

-   `bash` shell。
-   需要操作的工具必须已安装（例如，要管理 Trivy 数据库，目标机器上必须安装 `trivy`）。
-   常用的 Unix 工具，如 `tar`, `find`, `rm`, `mkdir`, `date` 等（大多数 Linux 发行版已内置）。

## 🚀 快速开始

脚本的核心使用流程分为两步：**在线下载**和**离线更新**。

### 1. 在线机器：下载并打包数据库

在任何一台可以访问互联网的机器上，运行 `download` 命令。

**对于 Trivy:**
```bash
./manage_scanner_db.sh trivy download
```
执行后，将在当前目录下生成一个名为 `trivy-database-YYYYMMDD.tar.gz` 的文件。

**对于 Grype:**
```bash
./manage_scanner_db.sh grype download
```
执行后，将在当前目录下生成一个名为 `grype-database-YYYYMMDD.tar.gz` 的文件。

### 2. 传输文件

将生成的 `.tar.gz` 压缩包通过任何方式（如 U 盘、内部文件服务器）传输到你的离线机器上，并确保脚本 `manage_scanner_db.sh` 也在这台机器上。

### 3. 离线机器：更新数据库

在离线机器上，将终端的工作目录切换到包含压缩包和脚本的目录下，然后运行 `update` 命令。

**更新 Trivy:**
```bash
./manage_scanner_db.sh trivy update
```

**更新 Grype:**
```bash
./manage_scanner_db.sh grype update
```
脚本会自动找到最新的数据库压缩包，备份现有数据，然后解压并完成更新。

## 📚 命令参考

基本用法: `./manage_scanner_db.sh <trivy|grype> [command]`

| 命令       | 描述                                                                                     |
| :--------- | :--------------------------------------------------------------------------------------- |
| `download` | **（在线使用）** 下载最新的数据库并将其打包成一个 `.tar.gz` 文件。                         |
| `update`   | **（离线使用）** 从当前目录中的 `.tar.gz` 文件解压并更新本地数据库。                        |
| `status`   | 显示当前本地数据库的详细状态，如缓存目录、大小、最后更新时间和备份数量。                   |
| `clean`    | 清理旧的数据库备份（超过30天）和旧的数据库压缩包（保留最新的3个）。                        |
| `help`     | 显示帮助信息。                                                                           |

### 示例

-   **查看 Trivy 数据库状态**
    ```bash
    ./manage_scanner_db.sh trivy status
    ```

-   **清理旧的 Grype 相关文件**
    ```bash
    ./manage_scanner_db.sh grype clean
    ```

## 📂 文件与目录结构

运行脚本后，你的工作目录和用户 `home` 目录将产生以下结构：

```
.
├── manage_scanner_db.sh                # 脚本本身
├── trivy-database-20231027.tar.gz      # Trivy 数据库压缩包
├── grype-database-20231026.tar.gz      # Grype 数据库压缩包
└── db-backups/                         # 自动创建的备份根目录
    ├── trivy/                          # Trivy 的备份
    │   └── trivy-db-backup-20231027-103000/
    └── grype/                          # Grype 的备份
        └── grype-db-backup-20231026-110000/

~/.cache/
├── trivy/                              # Trivy 的数据库缓存目录
│   ├── db/
│   └── java-db/
└── grype/                              # Grype 的数据库缓存目录
    └── db/
```

## 🛠️ 自定义配置

如果你需要修改脚本的默认行为（例如备份保留天数或Trivy的数据库镜像源），可以直接编辑脚本文件顶部的配置变量。

```bash
# 脚本顶部的配置变量
TRIVY_DB_REPO="ghcr.m.daocloud.io/aquasecurity/trivy-db"
TRIVY_JAVA_DB_REPO="ghcr.m.daocloud.io/aquasecurity/trivy-java-db"
...
# 在 clean_old_files 函数中可以修改备份保留时间和压缩包保留数量
find "$BACKUP_DIR" ... -mtime +30 ...
ls -t ... | tail -n +4
```
