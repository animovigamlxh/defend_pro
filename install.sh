#!/bin/bash

# 🗂️ Docker完整备份脚本
echo "🗂️ Docker环境备份开始..."

# 创建备份目录
BACKUP_DIR="docker_backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"
cd "$BACKUP_DIR"

echo "📂 备份目录: $(pwd)"

# 1. 备份所有镜像
echo "📦 备份Docker镜像..."
sudo docker save $(sudo docker images -q) > docker_images.tar
echo "✅ 镜像备份完成: docker_images.tar"

# 2. 备份所有卷
echo "💾 备份Docker卷..."
mkdir -p volumes
for volume in $(sudo docker volume ls -q); do
    echo "备份卷: $volume"
    sudo docker run --rm \
        -v $volume:/source \
        -v $(pwd)/volumes:/backup \
        ubuntu tar czf /backup/${volume}.tar.gz -C /source .
done
echo "✅ 卷备份完成"

# 3. 备份容器配置
echo "⚙️ 备份容器配置..."
sudo docker ps -a --format "table {{.Names}}\t{{.Image}}\t{{.Status}}" > containers_list.txt
sudo docker inspect $(sudo docker ps -aq) > containers_config.json
echo "✅ 容器配置备份完成"

# 4. 备份Docker网络
echo "🌐 备份Docker网络..."
sudo docker network ls > networks_list.txt
sudo docker network inspect $(sudo docker network ls -q) > networks_config.json
echo "✅ 网络配置备份完成"

# 5. 备份Docker Compose文件（如果存在）
echo "📋 搜索Docker Compose文件..."
find /home -name "docker-compose.yml" -o -name "docker-compose.yaml" 2>/dev/null > compose_files.txt
if [ -s compose_files.txt ]; then
    mkdir -p compose
    while read -r file; do
        cp "$file" "compose/$(basename $(dirname $file))_$(basename $file)"
    done < compose_files.txt
    echo "✅ Compose文件备份完成"
else
    echo "📝 未找到Compose文件"
fi

# 6. 创建恢复脚本
cat > restore.sh << 'EOF'
#!/bin/bash
echo "🔄 Docker环境恢复开始..."

# 恢复镜像
echo "📦 恢复Docker镜像..."
sudo docker load < docker_images.tar

# 恢复卷
echo "💾 恢复Docker卷..."
for volume_file in volumes/*.tar.gz; do
    if [ -f "$volume_file" ]; then
        volume_name=$(basename "$volume_file" .tar.gz)
        echo "恢复卷: $volume_name"
        sudo docker volume create "$volume_name"
        sudo docker run --rm \
            -v $volume_name:/target \
            -v $(pwd)/volumes:/backup \
            ubuntu tar xzf /backup/$(basename "$volume_file") -C /target
    fi
done

echo "✅ Docker环境恢复完成！"
echo "📋 请查看 containers_list.txt 手动重建容器"
EOF

chmod +x restore.sh

# 7. 压缩整个备份
cd ..
tar czf "${BACKUP_DIR}.tar.gz" "$BACKUP_DIR"

echo ""
echo "🎉 Docker备份完成！"
echo "📂 备份目录: $BACKUP_DIR"
echo "📦 压缩文件: ${BACKUP_DIR}.tar.gz"
echo "🔄 恢复脚本: $BACKUP_DIR/restore.sh"
echo ""
echo "💡 使用方法："
echo "  解压: tar xzf ${BACKUP_DIR}.tar.gz"
echo "  恢复: cd ${BACKUP_DIR} && sudo bash restore.sh" 
