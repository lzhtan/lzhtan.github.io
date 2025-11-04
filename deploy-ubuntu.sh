#!/bin/bash

# ========================================================
# 项目管理系统 - Ubuntu服务器部署脚本
# 版本: 1.2
# 最近更新:
# - 优化GitHub连接处理，区分连接超时和下载超时
# - 连接失败时快速重试，而不是等待下载超时
# - 添加--connect-timeout参数，允许自定义连接超时时间
# ========================================================

# 输出彩色文本的函数
print_green() {
  echo -e "\033[0;32m$1\033[0m"
}

print_yellow() {
  echo -e "\033[0;33m$1\033[0m"
}

print_red() {
  echo -e "\033[0;31m$1\033[0m"
}

print_blue() {
  echo -e "\033[0;34m$1\033[0m"
}

# 调试输出函数
debug_print() {
  if [ "$DEBUG_MODE" = true ]; then
    echo -e "\033[0;36m[DEBUG] $1\033[0m"
  fi
}

# 显示帮助信息
show_help() {
  echo "项目管理系统 - Ubuntu服务器部署脚本 使用说明"
  echo "用法: sudo bash deploy-ubuntu.sh [选项]"
  echo ""
  echo "选项:"
  echo "  --non-interactive     非交互模式，使用默认值自动执行"
  echo "  --fresh-install       全新安装（替换现有文件，会备份）"
  echo "  --no-backup-install   全新安装（替换现有文件，不备份）" 
  echo "  --update-only         仅更新代码（保留配置和数据）" 
  echo "  --redeploy-only       仅重新部署前后端（不更新代码）"
  echo "  --clean-backups       清理所有备份文件（删除备份目录）"
  echo "  --no-github           跳过GitHub克隆，使用本地代码"
  echo "  --clone-timeout=N     设置Git克隆超时时间（秒，默认180）"
  echo "  --connect-timeout=N   设置连接超时时间（秒，默认10）"
  echo "  --download-method=X   指定下载方法 (git|local|skeleton，默认git)"
  echo "  --local-path=PATH     指定本地代码路径（当download-method=local时使用）"
  echo "  --github-password=P   指定GitHub密码或令牌（当download-method=git时使用）"
  echo "  --debug               启用调试模式，显示详细输出"
  echo "  --help                显示此帮助信息"
  echo ""
  echo "示例:"
  echo "  sudo bash deploy-ubuntu.sh                          # 交互式安装"
  echo "  sudo bash deploy-ubuntu.sh --non-interactive        # 非交互式安装（默认更新）"
  echo "  sudo bash deploy-ubuntu.sh --non-interactive --fresh-install  # 非交互式全新安装（备份）"
  echo "  sudo bash deploy-ubuntu.sh --non-interactive --no-backup-install  # 非交互式全新安装（不备份）"
  echo "  sudo bash deploy-ubuntu.sh --clean-backups          # 清理所有备份文件"
  echo "  sudo bash deploy-ubuntu.sh --download-method=local --local-path=/path/to/code # 从本地目录复制代码"
  echo "  sudo bash deploy-ubuntu.sh --download-method=git --github-password=your_pwd  # 使用git克隆（提供密码）"
  echo "  sudo bash deploy-ubuntu.sh --download-method=skeleton  # 创建基本文件结构，不下载代码"
  echo "  sudo bash deploy-ubuntu.sh --download-method=git --github-password=your_pwd --debug  # 显示详细克隆过程"
  exit 0
}

# 默认设置为交互式模式
INTERACTIVE=true
DOWNLOAD_METHOD="auto"
CLONE_TIMEOUT=180  # 下载超时，单位秒
CONNECT_TIMEOUT=10 # 连接超时，单位秒
LOCAL_PATH=""
GITHUB_PASSWORD=""
DEBUG_MODE=false
FRESH_INSTALL=true
UPDATE_ONLY=false
REDEPLOY_ONLY=false  # 新增变量，只重新部署前后端，不更新代码
NO_BACKUP=false      # 新增变量，不备份直接重新安装
CLEAN_BACKUPS=false  # 新增变量，清理所有备份文件

# 解析命令行参数
for arg in "$@"; do
  case $arg in
    --non-interactive)
      INTERACTIVE=false
      shift
      ;;
    --fresh-install)
      FRESH_INSTALL=true
      UPDATE_ONLY=false
      REDEPLOY_ONLY=false
      NO_BACKUP=false
      shift
      ;;
    --no-backup-install)
      FRESH_INSTALL=true
      UPDATE_ONLY=false
      REDEPLOY_ONLY=false
      NO_BACKUP=true
      shift
      ;;
    --update-only)
      FRESH_INSTALL=false
      UPDATE_ONLY=true
      REDEPLOY_ONLY=false
      shift
      ;;
    --redeploy-only)  # 新增参数
      FRESH_INSTALL=false
      UPDATE_ONLY=false
      REDEPLOY_ONLY=true
      shift
      ;;
    --clean-backups)
      CLEAN_BACKUPS=true
      shift
      ;;
    --no-github)
      # 这个选项现在没有实际作用，保留为了向后兼容
      print_yellow "提示: --no-github 选项已弃用，使用 --download-method=local 代替"
      shift
      ;;
    --clone-timeout=*)
      CLONE_TIMEOUT="${arg#*=}"
      shift
      ;;
    --connect-timeout=*)
      CONNECT_TIMEOUT="${arg#*=}"
      shift
      ;;
    --download-method=*)
      DOWNLOAD_METHOD="${arg#*=}"
      shift
      ;;
    --local-path=*)
      LOCAL_PATH="${arg#*=}"
      shift
      ;;
    --github-password=*)
      GITHUB_PASSWORD="${arg#*=}"
      shift
      ;;
    --debug)
      DEBUG_MODE=true
      shift
      ;;
    --help)
      show_help
      ;;
    *)
      # 未知参数
      ;;
  esac
done

# 默认使用git下载方式
if [ -z "$DOWNLOAD_METHOD" ] || [ "$DOWNLOAD_METHOD" = "auto" ]; then
  DOWNLOAD_METHOD="git"
  print_yellow "默认使用git下载方式"
fi

# 显示脚本信息
print_blue "╔════════════════════════════════════════════════════════════╗"
print_blue "║                                                            ║"
print_blue "║        项目管理系统 - Ubuntu服务器部署脚本                  ║"
print_blue "║                                                            ║"
print_blue "╚════════════════════════════════════════════════════════════╝"
echo ""

# 用于在非交互模式下模拟用户输入的函数
auto_input() {
  if [ "$INTERACTIVE" = true ]; then
    read -p "$1" response
    echo "$response"
  else
    echo "$2" # 默认值
    print_yellow "非交互模式: 使用默认值 '$2'"
  fi
}

# 检查是否以root权限运行
if [ "$EUID" -ne 0 ]; then
  print_red "请以root权限运行此脚本"
  print_yellow "使用: sudo bash deploy-ubuntu.sh"
  exit 1
fi

# 检测Ubuntu版本
if [ -f /etc/os-release ]; then
  . /etc/os-release
  if [[ "$ID" != "ubuntu" ]]; then
    print_red "此脚本仅适用于Ubuntu系统"
    exit 1
  fi
  
  print_green "检测到 Ubuntu $VERSION_ID 系统"
else
  print_red "无法确定操作系统版本"
  exit 1
fi

# 设置部署目录
DEPLOY_DIR="/var/www/longrdma"
BACKUP_DIR="/var/www/longrdma_backups"

# 如果指定了清理备份选项，则清理备份目录后退出
if [ "$CLEAN_BACKUPS" = true ]; then
  if [ -d "$BACKUP_DIR" ]; then
    print_yellow "开始清理所有备份文件..."
    
    if [ "$INTERACTIVE" = true ]; then
      print_yellow "警告：即将删除目录 $BACKUP_DIR 中的所有文件！"
      print_yellow "此操作不可撤销！是否继续？ (y/n)"
      read confirm_clean
      
      if [[ "$confirm_clean" != "y" && "$confirm_clean" != "Y" ]]; then
        print_yellow "已取消清理操作"
        exit 0
      fi
    else
      print_yellow "非交互模式：自动确认清理所有备份"
    fi
    
    rm -rf $BACKUP_DIR
    mkdir -p $BACKUP_DIR
    print_green "所有备份文件已清理完毕！"
  else
    print_yellow "备份目录 $BACKUP_DIR 不存在，无需清理"
  fi
  exit 0
fi

# 检查是否存在旧安装
if [ -d "$DEPLOY_DIR" ]; then
  print_yellow "发现现有安装..."
  
  if [ "$REDEPLOY_ONLY" = true ]; then
    print_yellow "使用'仅重新部署'模式，跳过代码更新..."
    FRESH_INSTALL=false
    # 不设置install_choice，直接继续执行
  elif [ "$UPDATE_ONLY" = true ]; then
    print_yellow "保留现有安装，只更新代码..."
    # 备份重要配置文件
    mkdir -p /tmp/config_backup
    
    # 备份后端配置
    if [ -f "$DEPLOY_DIR/backend/.env" ]; then
      cp $DEPLOY_DIR/backend/.env /tmp/config_backup/
    fi
    
    # 备份PM2配置
    if [ -f "$HOME/.pm2/dump.pm2" ]; then
      cp $HOME/.pm2/dump.pm2 /tmp/config_backup/
    fi
    
    # 稍后将恢复这些文件
    FRESH_INSTALL=false
    install_choice="2"  # 设置为更新模式
  elif [ "$INTERACTIVE" = true ]; then
    print_yellow "检测到已存在的安装。请选择操作："
    print_yellow "1) 备份并重新安装 (将替换所有文件)"
    print_yellow "2) 保留数据并更新代码 (保留配置文件和数据库)"
    print_yellow "3) 取消安装"
    print_yellow "4) 不备份直接重新安装 (将直接删除所有文件，无备份)"
    read -p "请选择 [1-4]: " install_choice
  else
    # 在非交互模式下，根据参数选择操作
    if [ "$NO_BACKUP" = true ]; then
      install_choice="4"
      print_yellow "非交互模式: 选择不备份直接重新安装"
    elif [ "$FRESH_INSTALL" = true ]; then
      install_choice="1"
      print_yellow "非交互模式: 选择备份并重新安装"
    elif [ "$UPDATE_ONLY" = true ]; then
      install_choice="2"
      print_yellow "非交互模式: 选择仅更新代码"
    else
      install_choice="2" # 默认仅更新代码
      print_yellow "非交互模式: 默认选择仅更新代码"
    fi
  fi
  
  # 如果不是仅重新部署模式，则继续处理安装选择
  if [ "$REDEPLOY_ONLY" != true ]; then
    case $install_choice in
      1)
        # 创建备份目录
        mkdir -p $BACKUP_DIR
        
        # 备份时间戳
        TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
        BACKUP_PATH="$BACKUP_DIR/backup_$TIMESTAMP"
        
        print_yellow "正在备份现有安装到 $BACKUP_PATH..."
        cp -r $DEPLOY_DIR $BACKUP_PATH
        
        # 如果MongoDB数据也需要备份
        if [ -d "/var/lib/mongodb" ]; then
          if [ "$INTERACTIVE" = true ]; then
            print_yellow "是否同时备份MongoDB数据？ (y/n)"
            read backup_mongo
          else
            backup_mongo="y" # 在非交互模式下默认备份
            print_yellow "非交互模式: 默认备份MongoDB数据"
          fi
          
          if [[ "$backup_mongo" == "y" || "$backup_mongo" == "Y" ]]; then
            print_yellow "备份MongoDB数据..."
            
            # 停止MongoDB服务
            systemctl stop mongod
            
            # 备份数据目录
            mkdir -p $BACKUP_PATH/mongodb
            cp -r /var/lib/mongodb $BACKUP_PATH/mongodb/
            
            # 重启MongoDB服务
            systemctl start mongod
          fi
        fi
        
        print_green "备份完成！"
        print_yellow "移除现有安装..."
        rm -rf $DEPLOY_DIR
        FRESH_INSTALL=true
        ;;
        
      2)
        print_yellow "保留现有安装，只更新代码..."
        # 备份重要配置文件
        mkdir -p /tmp/config_backup
        
        # 备份后端配置
        if [ -f "$DEPLOY_DIR/backend/.env" ]; then
          cp $DEPLOY_DIR/backend/.env /tmp/config_backup/
        fi
        
        # 备份PM2配置
        if [ -f "$HOME/.pm2/dump.pm2" ]; then
          cp $HOME/.pm2/dump.pm2 /tmp/config_backup/
        fi
        
        # 稍后将恢复这些文件
        FRESH_INSTALL=false
        ;;
        
      3)
        print_red "安装已取消"
        exit 1
        ;;
      
      4)
        print_red "警告：将不备份直接删除现有安装！"
        if [ "$INTERACTIVE" = true ]; then
          print_yellow "确定要继续吗？这将永久删除所有数据。 (y/n)"
          read confirm_no_backup
          if [[ "$confirm_no_backup" != "y" && "$confirm_no_backup" != "Y" ]]; then
            print_yellow "操作已取消"
            exit 1
          fi
        else
          print_yellow "非交互模式: 直接执行不备份重新安装"
        fi
        
        print_yellow "直接移除现有安装，不创建备份..."
        rm -rf $DEPLOY_DIR
        FRESH_INSTALL=true
        ;;
        
      *)
        print_red "无效的选择，退出安装"
        exit 1
        ;;
    esac
  fi
else
  # 新安装
  if [ "$REDEPLOY_ONLY" = true ]; then
    print_red "错误: 没有找到现有安装，无法使用'仅重新部署'模式"
    exit 1
  fi
  FRESH_INSTALL=true
fi

# 安装必要的系统依赖
print_yellow "安装系统依赖..."
apt-get update
apt-get install -y curl git build-essential nginx

# 安装Node.js
print_yellow "安装Node.js..."
if ! command -v node &> /dev/null; then
  curl -fsSL https://deb.nodesource.com/setup_16.x | bash -
  apt-get install -y nodejs
fi

# 验证Node.js安装
NODE_VERSION=$(node -v)
print_green "Node.js安装完成: $NODE_VERSION"

# 安装MongoDB
if ! command -v mongod &> /dev/null; then
  print_yellow "安装MongoDB..."
  
  # 安装MongoDB
  apt-get install -y mongodb
  
  if [ $? -ne 0 ]; then
    print_red "MongoDB安装失败"
    exit 1
  fi
  
  print_green "MongoDB安装成功"
else
  print_green "MongoDB已安装"
  
  # 确保MongoDB服务已启动
  systemctl start mongod
  systemctl enable mongod
fi

# 下载或克隆应用代码
print_yellow "获取应用代码..."

# 如果是仅重新部署模式，跳过代码获取
if [ "$REDEPLOY_ONLY" = true ]; then
  print_yellow "仅重新部署模式，跳过代码获取步骤..."
else
  # 创建临时目录用于克隆
  TMP_CLONE_DIR="/tmp/longrdma_clone"
  rm -rf $TMP_CLONE_DIR
  mkdir -p $TMP_CLONE_DIR
  
  # 设置GitHub重试参数
  MAX_RETRIES=10
  RETRY_DELAY=0

  # 设置GitHub认证
  if [ -n "$GITHUB_PASSWORD" ]; then
    # 使用环境变量存储认证信息
    export GIT_ASKPASS=/tmp/git-askpass.sh
    cat > $GIT_ASKPASS << EOF
#!/bin/bash
echo "$GITHUB_PASSWORD"
EOF
    chmod +x $GIT_ASKPASS
    
    # 设置GitHub URL，包含用户名
    GITHUB_REPO="https://lzhtan@github.com/lzhtan/longrdma.git"
  else
    GITHUB_REPO="https://github.com/lzhtan/longrdma.git"
  fi

  # 克隆函数，带有重试机制
  clone_with_retry() {
    local retries=0
    local success=false
    
    # 设置Git全局用户名为lzhtan
    print_yellow "设置Git用户名: lzhtan"
    git config --global user.name "lzhtan"
    
    # 显示当前的Git配置
    if [ "$DEBUG_MODE" = true ]; then
      print_yellow "当前Git配置信息:"
      git config --global --list
    fi
    
    # 先移除可能存在的临时目录
    if [ -d "$TMP_CLONE_DIR" ]; then
      print_yellow "移除已存在的临时目录"
      rm -rf $TMP_CLONE_DIR
    fi
    mkdir -p $TMP_CLONE_DIR
    
    while [ $retries -lt $MAX_RETRIES ] && [ "$success" = false ]; do
      print_yellow "尝试从GitHub克隆代码 (尝试 $((retries+1))/$MAX_RETRIES)..."
      print_yellow "克隆仓库: $GITHUB_REPO"
      debug_print "目标目录: $TMP_CLONE_DIR"
      debug_print "连接超时: $CONNECT_TIMEOUT 秒, 下载超时: $CLONE_TIMEOUT 秒"
      
      # 使用GIT_TRACE输出详细的Git过程
      if [ "$DEBUG_MODE" = true ]; then
        export GIT_TRACE=1
        export GIT_CURL_VERBOSE=1
        debug_print "启用Git跟踪: GIT_TRACE=1"
      fi
      
      # 先使用ls-remote测试仓库可达性
      print_yellow "测试仓库可达性..."
      if timeout --foreground $CONNECT_TIMEOUT git ls-remote --quiet --exit-code $GITHUB_REPO >/dev/null 2>&1; then
        print_green "仓库可达，开始克隆..."
      else
        print_red "无法连接到仓库，退出代码: $?"
        retries=$((retries+1))
        
        if [ $retries -lt $MAX_RETRIES ]; then
          print_yellow "连接失败，将在 $RETRY_DELAY 秒后重试..."
          sleep $RETRY_DELAY
          continue
        else
          print_red "连接失败，达到最大重试次数"
          break
        fi
      fi
      
      # 直接尝试克隆，不进行连接测试
      print_yellow "直接尝试克隆代码..."
      if timeout --foreground $CLONE_TIMEOUT git clone --verbose --depth=1 $GITHUB_REPO $TMP_CLONE_DIR; then
        print_green "GitHub代码克隆成功！"
        success=true
        break # 成功后立即跳出循环
      else
        clone_exit_code=$?
        print_red "克隆失败，退出代码: $clone_exit_code"
        
        # 检查是否有部分克隆的内容
        if [ -d "$TMP_CLONE_DIR/.git" ]; then
          print_yellow "检测到部分已克隆内容，尝试继续克隆..."
          # 进入目录尝试继续下载
          cd $TMP_CLONE_DIR
          if timeout --foreground $CLONE_TIMEOUT git fetch origin; then
            print_green "获取更新成功!"
            print_yellow "检出main分支..."
            if git checkout -f origin/main; then
              print_green "检出成功，克隆完成!"
              success=true
              cd - > /dev/null
              break # 成功后立即跳出循环
            fi
          fi
          cd - > /dev/null
          print_red "继续克隆失败，删除部分克隆内容"
          rm -rf $TMP_CLONE_DIR
          mkdir -p $TMP_CLONE_DIR
        fi
      fi
      
      retries=$((retries+1))
      
      if [ $retries -lt $MAX_RETRIES ]; then
        print_yellow "尝试失败，将在 $RETRY_DELAY 秒后重试..."
        sleep $RETRY_DELAY
        # 增加每次重试的等待时间
      else
        print_red "尝试失败，达到最大重试次数"
        # 禁用调试输出
        if [ "$DEBUG_MODE" = true ]; then
          unset GIT_TRACE
          unset GIT_CURL_VERBOSE
        fi
      fi
    done
    
    # 禁用调试输出
    if [ "$DEBUG_MODE" = true ]; then
      unset GIT_TRACE
      unset GIT_CURL_VERBOSE
    fi
    
    if [ "$success" = true ]; then
      return 0
    else
      return 1
    fi
  }

  # 从本地目录复制
  copy_from_local() {
    if [ -z "$LOCAL_PATH" ]; then
      print_red "未指定本地代码路径，请使用 --local-path=PATH 参数"
      return 1
    fi
    
    if [ ! -d "$LOCAL_PATH" ]; then
      print_red "指定的本地路径 $LOCAL_PATH 不存在或不是目录"
      return 1
    fi
    
    print_yellow "从本地路径 $LOCAL_PATH 复制代码..."
    rm -rf $TMP_CLONE_DIR
    mkdir -p $TMP_CLONE_DIR
    
    # 使用rsync复制文件以保留权限
    if command -v rsync &> /dev/null; then
      rsync -a "$LOCAL_PATH/" $TMP_CLONE_DIR/
    else
      cp -r "$LOCAL_PATH/"* $TMP_CLONE_DIR/
      cp -r "$LOCAL_PATH/".[!.]* $TMP_CLONE_DIR/ 2>/dev/null || true
    fi
    
    if [ $? -eq 0 ]; then
      print_green "从本地路径复制成功"
      return 0
    else
      print_red "从本地路径复制失败"
      return 1
    fi
  }

  # 创建骨架目录结构
  create_skeleton() {
    print_yellow "创建基本项目骨架结构..."
    rm -rf $TMP_CLONE_DIR
    mkdir -p $TMP_CLONE_DIR
    
    # 创建基本目录结构
    mkdir -p $TMP_CLONE_DIR/backend/public/uploads
    mkdir -p $TMP_CLONE_DIR/backend/models
    mkdir -p $TMP_CLONE_DIR/backend/controllers
    mkdir -p $TMP_CLONE_DIR/backend/routes
    mkdir -p $TMP_CLONE_DIR/backend/middleware
    mkdir -p $TMP_CLONE_DIR/src/components
    mkdir -p $TMP_CLONE_DIR/src/pages
    mkdir -p $TMP_CLONE_DIR/src/context
    
    # 创建基本package.json
    cat > $TMP_CLONE_DIR/package.json << EOF
{
  "name": "longrdma",
  "version": "1.0.0",
  "private": true,
  "dependencies": {
    "@testing-library/jest-dom": "^5.16.5",
    "@testing-library/react": "^13.4.0",
    "@testing-library/user-event": "^13.5.0",
    "axios": "^1.3.4",
    "bootstrap": "^5.2.3",
    "react": "^18.2.0",
    "react-bootstrap": "^2.7.2",
    "react-dom": "^18.2.0",
    "react-router-dom": "^6.8.2",
    "react-scripts": "5.0.1",
    "web-vitals": "^2.1.4"
  },
  "scripts": {
    "start": "react-scripts start",
    "build": "react-scripts build",
    "test": "react-scripts test",
    "eject": "react-scripts eject"
  },
  "eslintConfig": {
    "extends": [
      "react-app",
      "react-app/jest"
    ]
  },
  "browserslist": {
    "production": [
      ">0.2%",
      "not dead",
      "not op_mini all"
    ],
    "development": [
      "last 1 chrome version",
      "last 1 firefox version",
      "last 1 safari version"
    ]
  },
  "proxy": "http://localhost:5001"
}
EOF
    
    # 创建基本后端package.json
    cat > $TMP_CLONE_DIR/backend/package.json << EOF
{
  "name": "longrdma-backend",
  "version": "1.0.0",
  "description": "Backend for RDMA research management system",
  "main": "server.js",
  "scripts": {
    "start": "node server.js",
    "dev": "nodemon server.js"
  },
  "dependencies": {
    "bcryptjs": "^2.4.3",
    "cookie-parser": "^1.4.6",
    "cors": "^2.8.5",
    "dotenv": "^16.0.3",
    "express": "^4.18.2",
    "jsonwebtoken": "^9.0.0",
    "mongoose": "^7.0.1",
    "multer": "^1.4.5-lts.1"
  },
  "devDependencies": {
    "nodemon": "^2.0.21"
  }
}
EOF
    
    # 创建基本server.js
    cat > $TMP_CLONE_DIR/backend/server.js << EOF
require('dotenv').config();
const express = require('express');
const mongoose = require('mongoose');
const cors = require('cors');
const path = require('path');
const cookieParser = require('cookie-parser');

// 创建Express应用
const app = express();
const PORT = process.env.PORT || 5001;

// 设置CORS中间件
const corsOptions = {
  origin: process.env.CORS_ORIGIN || 'http://localhost',
  credentials: true,
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization', 'X-Requested-With']
};
app.use(cors(corsOptions));

// 其他中间件
app.use(express.json());
app.use(cookieParser());
app.use('/uploads', express.static(path.join(__dirname, 'public/uploads')));

// 数据库连接
mongoose.connect(process.env.MONGO_URI, {
  useNewUrlParser: true,
  useUnifiedTopology: true
})
.then(() => console.log('MongoDB连接成功: ' + mongoose.connection.host))
.catch(err => console.log('MongoDB连接失败:', err));

// 路由
app.get('/', (req, res) => {
  res.json({ message: 'API服务器运行正常' });
});

// 导入路由
const authRoutes = require('./routes/authRoutes');
app.use('/api/auth', authRoutes);

// 启动服务器
app.listen(PORT, () => {
  console.log(\`服务器运行在端口 \${PORT}\`);
  console.log('允许的CORS来源: ' + (process.env.CORS_ORIGIN || 'http://localhost'));
});
EOF
    
    # 创建基本authRoutes.js
    cat > $TMP_CLONE_DIR/backend/routes/authRoutes.js << EOF
const express = require('express');
const router = express.Router();
const authController = require('../controllers/authController');
const { auth } = require('../middleware/authMiddleware');

// 登录路由
router.post('/login', authController.login);

// 注销路由
router.get('/logout', authController.logout);

// 获取当前用户信息
router.get('/me', auth, authController.getCurrentUser);

// 初始化管理员账户
router.get('/init', authController.initAdminAccount);

module.exports = router;
EOF
    
    # 创建基本authController.js
    cat > $TMP_CLONE_DIR/backend/controllers/authController.js << EOF
const User = require('../models/User');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');

// 生成JWT令牌
const generateToken = (id) => {
  return jwt.sign({ id }, process.env.JWT_SECRET, {
    expiresIn: '1d'
  });
};

// 登录
exports.login = async (req, res) => {
  try {
    const { username, password } = req.body;

    // 检查用户是否存在
    const user = await User.findOne({ username });
    if (!user) {
      return res.status(400).json({ message: '用户名或密码错误' });
    }

    // 验证密码
    const isMatch = await user.matchPassword(password);
    if (!isMatch) {
      return res.status(400).json({ message: '用户名或密码错误' });
    }

    // 生成令牌
    const token = generateToken(user._id);

    // 设置cookie
    res.cookie('jwt', token, {
      httpOnly: true,
      secure: process.env.NODE_ENV === 'production',
      maxAge: 24 * 60 * 60 * 1000 // 1天
    });

    res.json({
      _id: user._id,
      username: user.username,
      role: user.role
    });
  } catch (error) {
    res.status(500).json({ message: '服务器错误' });
  }
};

// 注销
exports.logout = (req, res) => {
  res.cookie('jwt', '', {
    httpOnly: true,
    expires: new Date(0)
  });
  res.json({ message: '注销成功' });
};

// 获取当前用户
exports.getCurrentUser = async (req, res) => {
  try {
    const user = await User.findById(req.user._id).select('-password');
    res.json(user);
  } catch (error) {
    res.status(500).json({ message: '服务器错误' });
  }
};

// 初始化管理员账户
exports.initAdminAccount = async (req, res) => {
  try {
    // 检查是否已有管理员
    const adminExists = await User.findOne({ role: 'admin' });
    
    if (adminExists) {
      return res.json({ message: '管理员账户已存在' });
    }

    // 创建默认管理员
    const salt = await bcrypt.genSalt(10);
    const hashedPassword = await bcrypt.hash('89FvhGwxZ2MwY:)Qo~cT', salt);
    
    const adminUser = await User.create({
      username: 'longrdma',
      password: hashedPassword,
      role: 'admin'
    });

    res.json({ message: '管理员账户创建成功', username: 'longrdma' });
  } catch (error) {
    res.status(500).json({ message: '服务器错误', error: error.message });
  }
};
EOF
    
    # 创建基本User模型
    cat > $TMP_CLONE_DIR/backend/models/User.js << EOF
const mongoose = require('mongoose');
const bcrypt = require('bcryptjs');

const UserSchema = new mongoose.Schema({
  username: {
    type: String,
    required: true,
    unique: true
  },
  password: {
    type: String,
    required: true
  },
  role: {
    type: String,
    enum: ['user', 'admin'],
    default: 'user'
  },
  createdAt: {
    type: Date,
    default: Date.now
  }
});

// 验证密码方法
UserSchema.methods.matchPassword = async function(enteredPassword) {
  return await bcrypt.compare(enteredPassword, this.password);
};

module.exports = mongoose.model('User', UserSchema);
EOF
    
    # 创建基本authMiddleware.js
    cat > $TMP_CLONE_DIR/backend/middleware/authMiddleware.js << EOF
const jwt = require('jsonwebtoken');
const User = require('../models/User');

exports.auth = async (req, res, next) => {
  try {
    const token = req.cookies.jwt;
    
    if (!token) {
      return res.status(401).json({ message: '需要登录' });
    }
    
    // 验证令牌
    const decoded = jwt.verify(token, process.env.JWT_SECRET);
    
    // 获取用户信息
    const user = await User.findById(decoded.id).select('-password');
    
    if (!user) {
      return res.status(401).json({ message: '用户未找到' });
    }
    
    req.user = user;
    next();
  } catch (error) {
    res.status(401).json({ message: '未授权，登录失败' });
  }
};

// 管理员权限检查
exports.admin = (req, res, next) => {
  if (req.user && req.user.role === 'admin') {
    next();
  } else {
    res.status(403).json({ message: '仅允许管理员访问' });
  }
};
EOF
    
    # 创建基本的React入口文件
    cat > $TMP_CLONE_DIR/src/index.js << EOF
import React from 'react';
import ReactDOM from 'react-dom/client';
import './index.css';
import App from './App';

const root = ReactDOM.createRoot(document.getElementById('root'));
root.render(
  <React.StrictMode>
    <App />
  </React.StrictMode>
);
EOF
    
    # 创建基本的App.js
    cat > $TMP_CLONE_DIR/src/App.js << EOF
import React from 'react';
import { BrowserRouter as Router, Routes, Route } from 'react-router-dom';
import 'bootstrap/dist/css/bootstrap.min.css';
import './App.css';

// 导入组件
import Login from './pages/Login';
import Dashboard from './pages/Dashboard';
import { AuthProvider } from './context/AuthContext';
import PrivateRoute from './components/PrivateRoute';

function App() {
  return (
    <AuthProvider>
      <Router>
        <Routes>
          <Route path="/login" element={<Login />} />
          <Route 
            path="/*" 
            element={
              <PrivateRoute>
                <Dashboard />
              </PrivateRoute>
            } 
          />
        </Routes>
      </Router>
    </AuthProvider>
  );
}

export default App;
EOF

    # 创建index.html
    cat > $TMP_CLONE_DIR/public/index.html << EOF
<!DOCTYPE html>
<html lang="zh-CN">
  <head>
    <meta charset="utf-8" />
    <link rel="icon" href="%PUBLIC_URL%/favicon.ico" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <meta
      name="description"
      content="RDMA研究管理系统"
    />
    <title>RDMA研究管理系统</title>
  </head>
  <body>
    <noscript>您需要启用JavaScript来运行此应用。</noscript>
    <div id="root"></div>
  </body>
</html>
EOF

    # 创建基本的public目录
    mkdir -p $TMP_CLONE_DIR/public
    
    print_green "基本项目骨架结构创建成功"
    return 0
  }

  # 根据指定方式获取代码
  if [[ "$DOWNLOAD_METHOD" == "git" ]]; then
    # 使用git克隆代码
    print_yellow "使用git克隆代码..."
    if ! clone_with_retry; then
      print_red "克隆失败: 无法使用git获取代码，退出部署"
      exit 1
    fi
  elif [[ "$DOWNLOAD_METHOD" == "local" ]]; then
    if ! copy_from_local; then
      print_red "本地复制失败: 无法从本地目录获取代码，退出部署"
      exit 1
    fi
  elif [[ "$DOWNLOAD_METHOD" == "skeleton" ]]; then
    if ! create_skeleton; then
      print_red "创建骨架失败: 无法创建项目骨架结构，退出部署"
      exit 1
    fi
  else
    # 默认使用git
    print_yellow "使用git克隆代码..."
    if ! clone_with_retry; then
      print_red "克隆失败: 无法使用git获取代码，退出部署"
      exit 1
    fi
  fi
fi

# 确保目标部署目录存在
mkdir -p $DEPLOY_DIR

# 复制项目文件到部署目录
if [ "$REDEPLOY_ONLY" = true ]; then
  print_yellow "仅重新部署模式，跳过文件复制步骤..."
else
  print_yellow "复制项目文件到部署目录..."
  # 如果是更新代码，保留特定文件
  if [ "$FRESH_INSTALL" = false ]; then
    # 排除某些目录的复制
    exclude_dirs=(".git" "node_modules" "backend/node_modules" "backend/public/uploads")
    
    # 保存要排除的目录列表
    EXCLUDE_OPTS=""
    for dir in "${exclude_dirs[@]}"; do
      EXCLUDE_OPTS="$EXCLUDE_OPTS --exclude=$dir"
    done
    
    # 使用rsync而不是cp，它可以排除特定目录
    apt-get install -y rsync
    rsync -a $EXCLUDE_OPTS $TMP_CLONE_DIR/ $DEPLOY_DIR/
    
    # 恢复之前备份的配置文件
    if [ -f "/tmp/config_backup/.env" ]; then
      print_yellow "恢复后端环境配置..."
      cp /tmp/config_backup/.env $DEPLOY_DIR/backend/.env
    fi
    
    if [ -f "/tmp/config_backup/dump.pm2" ]; then
      print_yellow "恢复PM2配置..."
      cp /tmp/config_backup/dump.pm2 $HOME/.pm2/
    fi
    
    # 清理临时配置备份
    rm -rf /tmp/config_backup
  else
    # 新安装，直接复制所有文件
    cp -r $TMP_CLONE_DIR/* $DEPLOY_DIR/
    cp -r $TMP_CLONE_DIR/.* $DEPLOY_DIR/ 2>/dev/null || true
  fi
fi

# 清理临时目录
rm -rf $TMP_CLONE_DIR

# 安装后端依赖
cd $DEPLOY_DIR/backend

if [ "$REDEPLOY_ONLY" = true ]; then
  print_yellow "仅重新部署模式，检查依赖是否完整..."
  
  # 检查关键认证依赖是否已安装
  if ! npm list bcryptjs jsonwebtoken cookie-parser | grep -q "bcryptjs"; then
    print_yellow "安装缺失的认证依赖..."
    npm install bcryptjs jsonwebtoken cookie-parser --save
  fi
elif [ "$FRESH_INSTALL" = true ]; then
  # 全新安装所有依赖
  print_yellow "安装后端依赖..."
  npm install --production
  npm install bcryptjs jsonwebtoken cookie-parser --save
else
  # 更新安装，只安装新增依赖
  print_yellow "更新后端依赖..."
  npm install --no-save
  # 确保必要的认证模块已安装
  if ! npm list bcryptjs jsonwebtoken cookie-parser | grep -q "bcryptjs"; then
    npm install bcryptjs jsonwebtoken cookie-parser --save
  fi
fi

# 安装PM2进程管理器
print_yellow "安装PM2进程管理器..."
npm install -g pm2

# 创建环境配置文件
print_yellow "创建后端配置文件..."
if [ "$FRESH_INSTALL" = true ] || [ ! -f "$DEPLOY_DIR/backend/.env" ]; then
  # 生成随机JWT密钥
  JWT_SECRET=$(openssl rand -hex 32)
  
  IP_ADDRESS=$(hostname -I | awk '{print $1}')
  
  cat > $DEPLOY_DIR/backend/.env << EOF
PORT=5001
MONGO_URI=mongodb://localhost:27017/research-management
JWT_SECRET=$JWT_SECRET
NODE_ENV=production
UPLOAD_PATH=./public/uploads
CORS_ORIGIN=http://$IP_ADDRESS
EOF
  print_green "后端配置文件已创建"
else
  print_green "使用现有后端配置文件"
  
  # 更新CORS_ORIGIN，确保配置了正确域名
  if ! grep -q "CORS_ORIGIN" "$DEPLOY_DIR/backend/.env"; then
    echo "CORS_ORIGIN=http://$IP_ADDRESS" >> $DEPLOY_DIR/backend/.env
    print_yellow "添加了CORS_ORIGIN配置: http://$IP_ADDRESS"
  fi
fi

# 确保上传目录存在并有正确的权限
mkdir -p $DEPLOY_DIR/backend/public/uploads/papers
chown -R www-data:www-data $DEPLOY_DIR/backend/public/uploads

# 确保MongoDB服务正在运行
print_yellow "检查MongoDB服务状态..."
if ! systemctl is-active --quiet mongodb; then
  print_yellow "启动MongoDB服务..."
  systemctl start mongodb
  systemctl enable mongodb
fi

# 等待MongoDB完全启动
print_yellow "等待MongoDB服务完全启动..."
sleep 2

# 检查MongoDB连接
print_yellow "检查MongoDB连接..."
if ! mongo --eval "db.adminCommand('ping')" > /dev/null 2>&1; then
  print_red "MongoDB连接失败，请检查MongoDB服务是否正常运行"
  exit 1
fi

# 创建数据库和初始集合
print_yellow "初始化数据库..."
mongo --eval "use research-management; db.createCollection('papers'); db.createCollection('users')" > /dev/null 2>&1

# 更新后端环境配置
print_yellow "更新后端环境配置..."
cat > $DEPLOY_DIR/backend/.env << EOF
PORT=5001
MONGO_URI=mongodb://localhost:27017/research-management
JWT_SECRET=$JWT_SECRET
NODE_ENV=production
UPLOAD_PATH=public/uploads
CORS_ORIGIN=http://$IP_ADDRESS
EOF

# 更新前端环境配置
print_yellow "更新前端环境配置..."
echo "REACT_APP_API_BASE_URL=/api" > $DEPLOY_DIR/.env

# 构建前端代码
cd $DEPLOY_DIR

# 确保.env文件配置正确
print_yellow "配置前端环境变量..."
echo "REACT_APP_API_BASE_URL=/api" > $DEPLOY_DIR/.env
print_green "已设置API基础URL为相对路径: /api"

if [ "$REDEPLOY_ONLY" = true ]; then
  print_yellow "仅重新部署模式，检查前端构建..."
  
  # 检查前端构建是否存在
  if [ ! -d "$DEPLOY_DIR/build" ]; then
    print_yellow "未找到前端构建目录，需要重新构建前端..."
    npm install
    npm run build
  else
    print_green "前端构建目录已存在，无需重新构建。"
  fi
else
  print_yellow "构建前端代码..."
  # 如果build目录不存在，自动重新构建前端
  if [ ! -d "$DEPLOY_DIR/build" ]; then
    print_yellow "构建目录不存在，重新构建前端..."
    npm install
    npm run build
  else
    # 如果是更新安装且在交互模式下，询问是否重新构建前端
    if [ "$FRESH_INSTALL" = false ]; then
      if [ "$INTERACTIVE" = true ]; then
        print_yellow "是否重新构建前端？ (y/n)"
        read rebuild_frontend
      else
        rebuild_frontend="y" # 在非交互模式下默认重新构建
        print_yellow "非交互模式: 默认重新构建前端"
      fi
      
      if [[ "$rebuild_frontend" == "y" || "$rebuild_frontend" == "Y" ]]; then
        npm install
        npm run build
      else
        print_green "保留现有前端构建"
      fi
    fi
  fi
fi

# 配置Nginx
print_yellow "配置Nginx..."

# 获取服务器IP
IP_ADDRESS=$(hostname -I | awk '{print $1}')

cat > /etc/nginx/sites-available/longrdma << EOF
server {
    listen 80;
    listen [::]:80;
    server_name _;  # 使用服务器IP访问，如有域名请替换
    
    client_max_body_size 50M;
    # 前端静态文件
    location / {
        root /var/www/longrdma/build;
        index index.html;
        try_files \$uri \$uri/ /index.html;
    }
    
    # 后端API代理
    location /api {
        proxy_pass http://localhost:5001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
        
        # 允许跨域cookies
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # CORS headers - 使用具体域名而不是通配符
        add_header 'Access-Control-Allow-Origin' 'http://$IP_ADDRESS';
        add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS, PUT, DELETE';
        add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range,Authorization';
        add_header 'Access-Control-Expose-Headers' 'Content-Length,Content-Range';
        add_header 'Access-Control-Allow-Credentials' 'true';
        
        # 处理OPTIONS预检请求
        if (\$request_method = 'OPTIONS') {
            add_header 'Access-Control-Allow-Origin' 'http://$IP_ADDRESS';
            add_header 'Access-Control-Allow-Methods' 'GET, POST, OPTIONS, PUT, DELETE';
            add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range,Authorization';
            add_header 'Access-Control-Max-Age' 1728000;
            add_header 'Access-Control-Allow-Credentials' 'true';
            add_header 'Content-Type' 'text/plain; charset=utf-8';
            add_header 'Content-Length' 0;
            return 204;
        }
    }
    
    # 上传文件目录
    location /uploads {
        alias /var/www/longrdma/backend/public/uploads;
    }
}
EOF

# 启用网站配置
ln -sf /etc/nginx/sites-available/longrdma /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

# 检查Nginx配置是否有效
nginx -t

if [ $? -ne 0 ]; then
  print_red "Nginx配置无效，请检查错误"
  exit 1
fi

# 重启Nginx
systemctl restart nginx
systemctl enable nginx

# 使用PM2启动后端服务
print_yellow "启动应用服务..."
cd $DEPLOY_DIR/backend

# 检查端口占用情况
PORT_NUMBER=5001
print_yellow "检查端口 $PORT_NUMBER 是否被占用..."
PORT_PIDS=$(lsof -t -i:$PORT_NUMBER 2>/dev/null || echo "")

if [ ! -z "$PORT_PIDS" ]; then
  print_yellow "发现占用端口 $PORT_NUMBER 的进程，进程ID: $PORT_PIDS"
  for PID in $PORT_PIDS; do
    print_yellow "正在终止进程 $PID..."
    kill -9 $PID || print_red "警告: 无法终止进程 $PID"
  done
  print_green "端口冲突已解决"
fi

# 检查是否已有PM2进程运行
if pm2 list | grep -q "longrdma-api"; then
  print_yellow "发现正在运行的服务，正在重启..."
  # 先尝试重新加载，如果失败则重启服务
  if ! pm2 reload longrdma-api; then
    print_yellow "重新加载失败，尝试重启服务..."
    pm2 stop longrdma-api
    pm2 delete longrdma-api
    pm2 start server.js --name "longrdma-api"
  fi
else
  print_yellow "启动新的服务实例..."
  pm2 start server.js --name "longrdma-api"
fi

pm2 save
pm2 startup

# 仅在全新安装时初始化管理员账户
if [ "$FRESH_INSTALL" = true ]; then
  print_yellow "初始化管理员账户..."
  
  # 等待服务器完全启动（增加等待时间）
  print_yellow "等待后端服务完全启动..."
  sleep 3
  
  # 检查后端服务是否正常运行
  if ! curl -s http://localhost:5001 > /dev/null; then
    print_yellow "后端服务未响应，检查服务状态..."
    pm2 status
    
    # 检查端口是否被占用
    PORT_PIDS=$(lsof -t -i:5001 2>/dev/null || echo "")
    if [ ! -z "$PORT_PIDS" ]; then
      print_yellow "发现端口5001被占用，尝试释放..."
      for PID in $PORT_PIDS; do
        kill -9 $PID
      done
      
      # 重启服务
      print_yellow "重启后端服务..."
      pm2 restart longrdma-api
      sleep 3
    else
      # 如果端口未被占用但服务未响应，可能是服务有错误
      print_yellow "检查服务日志..."
      pm2 logs --lines 20 longrdma-api
      
      # 强制重启服务
      print_yellow "尝试完全重启服务..."
      pm2 stop longrdma-api
      pm2 delete longrdma-api
      cd $DEPLOY_DIR/backend
      pm2 start server.js --name "longrdma-api"
      sleep 3
    fi
  fi
  
  # 尝试调用初始化API，使用更多重试
  MAX_RETRIES=5
  retry_count=0
  init_success=false
  
  while [ $retry_count -lt $MAX_RETRIES ] && [ "$init_success" = false ]; do
    print_yellow "尝试初始化管理员账户 (尝试 $((retry_count+1))/$MAX_RETRIES)..."
    
    response=$(curl -s -X GET http://localhost:5001/api/auth/init)
    debug_print "初始化API响应: $response"
    
    if [[ "$response" == *"管理员账户创建成功"* || "$response" == *"系统已初始化"* || "$response" == *"管理员账户已存在"* ]]; then
      print_green "管理员账户初始化成功!"
      init_success=true
    else
      print_yellow "初始化失败，等待1秒后重试..."
      sleep 1
      retry_count=$((retry_count+1))
    fi
  done
  
  if [ "$init_success" = false ]; then
    print_red "管理员账户初始化失败，请在系统启动后手动初始化"
    print_yellow "使用以下命令进行初始化: curl -X GET http://localhost:5001/api/auth/init"
    print_yellow "或检查服务是否正常运行: pm2 logs longrdma-api"
  fi
else
  print_yellow "使用现有管理员账户"
fi


# 创建系统服务
print_yellow "创建系统服务..."
cat > /etc/systemd/system/longrdma.service << EOF
[Unit]
Description=项目管理系统
After=network.target mongodb.service

[Service]
Type=forking
User=root
WorkingDirectory=/var/www/longrdma
ExecStart=/usr/local/bin/pm2 start /var/www/longrdma/backend/server.js --name "longrdma-api"
ExecReload=/usr/local/bin/pm2 reload longrdma-api
ExecStop=/usr/local/bin/pm2 stop longrdma-api
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# 重新加载systemd
systemctl daemon-reload
systemctl enable longrdma.service

# 显示完成信息
IP_ADDRESS=$(hostname -I | awk '{print $1}')

print_green "\n部署完成！"
print_blue "╔════════════════════════════════════════════════════════════╗"
print_blue "║                                                            ║"
print_blue "║  项目管理系统已成功部署                                     ║"
print_blue "║                                                            ║"
print_blue "║  访问地址: http://$IP_ADDRESS                              ║"
print_blue "║                                                            ║"
print_blue "║  默认管理员账户:                                           ║"
print_blue "║    用户名: longrdma                                        ║"
print_blue "║    密码: 89FvhGwxZ2MwY:)Qo~cT                              ║"
print_blue "║                                                            ║"
print_blue "║  部署目录: $DEPLOY_DIR                                      ║"
print_blue "║  数据库名: research-management                              ║"
print_blue "║                                                            ║"
print_blue "║  重新部署命令: sudo bash deploy-ubuntu.sh --redeploy-only   ║"
print_blue "║                                                            ║"
print_blue "╚════════════════════════════════════════════════════════════╝"

# 如果是redeploy-only模式，给予额外的重启提示
if [ "$REDEPLOY_ONLY" = true ]; then
  print_yellow "\n系统已重新部署。如果仍然遇到登录问题，请尝试以下步骤："
  print_yellow "1. 清除浏览器缓存和cookies"
  print_yellow "2. 确认API响应: curl -v http://localhost:5001/api/auth/login -H \"Content-Type: application/json\" -d '{\"username\":\"longrdma\",\"password\":\"89FvhGwxZ2MwY:)Qo~cT\"}'"
  print_yellow "3. 检查Nginx配置: nginx -t"
  print_yellow "4. 检查前端环境变量: cat $DEPLOY_DIR/.env"
fi 