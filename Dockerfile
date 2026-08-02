FROM opengauss/opengauss:latest

# openGauss 7.0-RC3 lite 镜像缺少 gaussdb 运行时依赖 libopenblas.so.0。
# openEuler 22.03 官方仓库的 openblas RPM 提供 /usr/lib64/libopenblas.so.0，
# 安装后 ld.so 缓存即可让 gaussdb 正常加载。
USER root
RUN yum install -y openblas \
    && yum clean all \
    && rm -rf /var/cache/yum

# 保留原镜像的 ENTRYPOINT/CMD/USER（默认 root，entrypoint.sh 内部切到 omm）
