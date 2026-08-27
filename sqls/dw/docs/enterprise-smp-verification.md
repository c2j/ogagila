# 企业版/极简版 SMP 验证操作指引

**适用场景**：在 x86_64 Linux 或鲲鹏（AArch64）服务器上部署 openGauss 企业版/极简版，
执行 `qa-enterprise.sh` 完成 V1（O1/O3 裁定）、V15（DBE_SCHEDULER）、SMP 加速比验证。

**背景**：本机（Apple Silicon Docker）已穷尽程序化路径（G40/G41/G41 后续段）：
- 4 个 Docker 镜像（7.0.1/5.0.0 lite、RC2/RC3 enterprise）均无 SMP（计时 ≈1.01x）
- OBS 桶列举被拒、核心包 URL 由 JS 生成、极简版包名全探测未命中
- **极简版/企业版二进制只能人工从官网下载，或使用真机**

---

## 一、获取极简版二进制（人工步骤）

### 方式 A：官网下载页（推荐）

1. 打开 https://opengauss.org/zh/download/ ，选择目标版本（建议 7.0.0 或 6.0.5 LTS）
2. 选择**架构**：AArch64（鲲鹏/Apple Silicon 服务器）或 x86_64
3. 选择**操作系统**：openEuler 22.03 LTS（推荐）或 CentOS 7.6
4. 展开 **极简版** 标签，下载 `openGauss-*-openEuler22.03-<arch>.tar.gz`
   （轻量版是 `openGauss-Lite-*`，**注意区分**：极简版才含 SMP/LLVM/向量化）
5. 同时下载同名 `.sha256` 校验文件

### 方式 B：OBS 直链（需已知确切包名，供脚本化参考）

```bash
# 轻量版示例（已验证存在，6.0.5 AArch64）：
wget https://opengauss.obs.cn-south-1.myhuaweicloud.com/6.0.5/openEuler22.03/arm/openGauss-Lite-6.0.5-openEuler22.03-aarch64.tar.gz
# 极简版/企业版包名需从方式 A 页面点击后复制链接（JS 渲染，无法脚本化）
```

### 校验与解包

```bash
sha256sum -c openGauss-*.tar.gz.sha256
tar -zxf openGauss-*.tar.gz          # 解出 openGauss-*/ 目录
```

---

## 二、部署单节点实例

以 openEuler/其他 Linux 服务器为例（容器内同理，见下）：

```bash
# 1. 创建运行用户（openGauss 禁止 root 运行）
useradd -m omm
su - omm

# 2. 安装依赖（openEuler）
sudo yum install -y libaio-devel flex bison ncurses-devel glibc-devel patch readline-devel

# 3. 解包并设置环境
tar -zxf openGauss-*.tar.gz -C /opt
echo "export GAUSSHOME=/opt/openGauss
export PATH=\$GAUSSHOME/bin:\$PATH
export LD_LIBRARY_PATH=\$GAUSSHOME/lib:\$LD_LIBRARY_PATH
export PGDATA=/opt/openGauss/data" >> ~/.bashrc
source ~/.bashrc

# 4. 初始化
gs_initdb -D \$PGDATA --nodename=og1 -U gaussdb -W 'Enmo@123' --encoding=UTF8

# 5. 启动
gs_ctl start -D \$PGDATA

# 6. 验证
gsql -d postgres -U gaussdb -W Enmo@123 -c "SELECT version();"
```

> **容器内部署**（若有 openEuler 容器）：步骤同上，`gs_initdb`/`gs_ctl` 用相同二进制。
> 注意：容器内需 `--privileged=true` 且建议显式设置 `max_process_memory` 等内存参数
> （参考本仓库 RC3 探针的 `OTHER_PG_CONF` 用法）。

---

## 三、验证 SMP 是否真可用（部署后先自检）

在部署的实例上执行（**先确认带 SMP 再跑完整套件**，避免白跑）：

```sql
-- 1. 确认 GUC 存在且可调
SELECT name, setting FROM pg_settings
 WHERE name IN ('query_dop','enable_vector_engine','enable_codegen','enable_smp');

-- 2. 灌 500 万行列存（验证向量化）
CREATE TABLE t_smp (k int, v numeric(18,2)) WITH (ORIENTATION=COLUMN, COMPRESSION=HIGH);
INSERT INTO t_smp SELECT n%10000, (n%1000)*0.01 FROM generate_series(1,5000000) n;

-- 3. 计划对比：dop=4 应出现 Streaming/并行算子
SET query_dop=4;
EXPLAIN (COSTS OFF) SELECT k, count(*), sum(v) FROM t_smp GROUP BY k;
--    若出现 "Streaming" 或 "dop: 1/N" → SMP 生效 ✅
--    若无 → 该包仍无 SMP（如误下载轻量版），停止
```

---

## 四、运行完整验证套件

确认 SMP 生效后，加载数据并运行套件：

```bash
# 1. 加载 DW 全套（若服务器是干净 openGauss，需要先建库对象）
#    方式：把本仓库 sqls/dw/ 拷贝到服务器，按 AGENTS.md 的 9-dw-* 顺序执行
#    （或直接复用本仓库 docker-compose，把镜像换成企业版/极简版部署的容器）

# 2. T3 规模造数（探针需要 ≥100 万行，计时下限 100ms 才可信）
bash sqls/dw/tests/fixtures/t3-scale.sh --rentals 2000000 --payments 10000000 --months 12

# 3. 运行企业版验证套件（三重防假阳性：数据下限 / MIN_BASE_MS / 统一探针 SQL）
CONTAINER=<企业版/极简版容器名> bash sqls/dw/tests/qa-enterprise.sh
```

### 预期输出解读

| 输出 | 含义 | 后续动作 |
|---|---|---|
| `SMP 加速比 > 1.15x` | SMP 生效 | 继续看 V1 裁定 |
| `过程内无提速` | G13 对 EXECUTE IMMEDIATE 生效 | **维持 O1**（队列模式，现状） |
| `过程内也有提速` | G13 不覆盖 EXECUTE IMMEDIATE | **可简化为 O3**（纯库内，移除 worker） |
| `base 中位 < 100ms → INCONCLUSIVE` | 数据不足 | 加大 T3 行数后重跑 |
| `dbe_scheduler 存在` | V15 通过 | 可评估库内调度替代外部 cron |

---

## 五、验证后回写

1. 把 `qa-enterprise.sh` 输出保存为 `sqls/dw/docs/enterprise-result-<arch>-<version>.md`
2. 更新 `.sisyphus/plans/opengauss-tiered-reporting.md`：
   - V1 结论 → 决定 §5.3 用 O1 还是 O3，并同步 `PKG_ORCH` 默认模式
   - V15 结论 → 决定是否引入 DBE_SCHEDULER
   - SMP 加速比 → 更新 §11 容量阈值判断（"单次 ETL 串行 > 30 分钟"是否需要下调）
3. 若极简版 KVecturbo 同样崩溃（CPU 特性问题），记录并退回真机方案

---

## 已知风险

- **极简版可能同样带 KVecturbo**：若部署后启动即退（报 `KVecturbo: ... CPU architect`），
  说明该包与 RC2 企业版镜像同问题，只能走 x86_64/鲲鹏真机（G37）。
- **openEuler 版本匹配**：包是为特定 openEuler 编译的，CentOS/其他发行版可能缺 glibc 依赖。
- **容器 vs 裸机**：容器部署需注意内存参数（`max_process_memory`），参考 RC3 探针经验。
