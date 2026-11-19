# SukiSU-Ultra 内核编译工具

依据官方集成教程 [sukisu.org/zh/guide/how-to-integrate](https://sukisu.org/zh/guide/how-to-integrate) 编写的一键式内核编译工具。

**核心流程:选设备型号 → 选内核版本 → 选集成分支 → 自动下载源码和工具链 → 集成 SukiSU-Ultra → 编译内核 → 打包产物。**

> 🌐 **在线编译**: 本仓库自带 GitHub Actions 工作流与网页,不用本地环境也能编译 ——
> 打开 <https://xingyiqaq.github.io/sukisu-kernel-builder/>,选机型/版本,一键触发云端编译,实时看进度、下载产物。

```
┌─────────────┐   ┌──────────────┐   ┌────────────────┐   ┌──────────────┐
│ 选设备型号   │ → │ 选内核版本    │ → │ 选 main/builtin│ → │ 自动编译打包  │
│ devices.conf│   │ (仓库+分支)   │   │ KSU 分支        │   │ AK3 zip / .ko│
└─────────────┘   └──────────────┘   └────────────────┘   └──────────────┘
```

## 〇、网页在线编译(GitHub Actions)

无需本地 Linux 环境,浏览器里选好机型直接编译:

1. 打开 <https://xingyiqaq.github.io/sukisu-kernel-builder/>
2. 填入一个 GitHub Token(需 `repo` + `workflow` 权限;只保存在浏览器 localStorage,不会上传)
3. 选设备型号 → 内核版本 → SukiSU 分支 → 点「开始编译」
4. 页面实时显示步骤状态(每 3 秒刷新)与构建日志(每 10 秒刷新;GitHub 对进行中任务的日志接口有延迟,想看完整实时日志可在页面上点「在 GitHub 打开」);完成后直接点「下载」拿 AnyKernel3 zip / kernelsu.ko

也可在 GitHub 仓库页面 **Actions → SukiSU Kernel Build → Run workflow** 手动触发。

**注意事项(公共 runner 限制):**
- 每个编译任务在 GitHub 公共 runner(2 核 7GB 内存)上执行,一次完整编译约 30 分钟~3 小时(取决于内核),单任务上限 6 小时;
- 产物保留 **14 天**(GitHub artifact 策略),请及时下载;
- 公共仓库的编译任务对所有人可见,如需私密构建可 fork 成私有仓库(私有仓库用 GitHub Pages 需要付费套餐,网页请改在本地打开 `index.html`)。

## 一、环境要求(本地编译)

- **Linux**(Ubuntu 20.04+ / Debian / WSL2),脚本不能直接在 Windows 上运行
- 网络通畅(需访问 GitHub 与 android.googlesource.com)
- 磁盘 **50GB+** 空闲(工具链约 3GB + 内核源码数 GB + 编译产物)
- 内存 **8GB+**(编译内核较吃内存),CPU 核越多越快

WSL2 用户先装 Ubuntu 发行版,进入后:

```bash
sudo apt update && sudo apt install -y git curl make gcc g++ bc bison flex libssl-dev libncurses-dev zip cpio python3
```

## 二、快速开始

```bash
# 进入工具目录(Windows 的 E 盘在 WSL 里是 /mnt/e)
cd /mnt/e/文档/deepseek-harness/default-workspace/sukisu-kernel-builder

# 交互式运行: 按提示选型号、选内核版本、选集成分支即可
bash build.sh
```

**交互示例**(选 Redmi K40 的 Android 11 内核,main 分支):

```
  [信息] 请选择设备型号:
      1) Redmi K40 / POCO F3
      2) Redmi K20 Pro / Mi 9T Pro
      ...
  >> 输入编号选择, 或输入关键词过滤 [默认 1]: k40        ← 支持关键词过滤
  ...
  >> 输入编号选择 [默认 1]: 1                            ← 该设备只有 1 个内核版本时自动跳过
  [信息] 请选择 SukiSU 集成分支:
      1) main —— Kprobes 运行时 hook (教程默认, 推荐)
      2) builtin —— 不使用 Kprobes, 自动 hook 替代
  >> 1
  [信息] ==================== 编译任务 ====================
  设备       : Redmi K40 / POCO F3 (alioth)
  内核版本   : Android 11 · Linux 4.19
  仓库/分支  : https://github.com/MiCode/Xiaomi_Kernel_OpenSource @ alioth-r-oss
  ...
  开始编译? [Y/n]
```

随后自动完成:下载 Clang 工具链 → 克隆内核源码 → 运行官方 `setup.sh` 集成 SukiSU → 生成 defconfig 并启用 `CONFIG_KSU/KPROBES/EXT4_FS/KALLSYMS` → `make -j$(nproc)` 编译 → 打包。

## 三、命令行参数(非交互 / 自动化)

| 参数 | 说明 |
|---|---|
| `--list` | 列出设备库全部条目 |
| `--device <id>` | 直接指定设备 ID(如 `alioth`) |
| `--version <n>` | 该设备第 n 个内核版本(配合 `--device`) |
| `--branch <名称>` | 直接指定内核分支,可单独使用自动反查设备 |
| `--repo <url>` | 自定义内核仓库(绕过设备库,配合 `--branch`) |
| `--defconfig <路径>` | 指定 defconfig(如 `vendor/alioth_user_defconfig`) |
| `--kver <x.y>` / `--android <n>` | 自定义源时声明内核/Android 版本(用于选编译器) |
| `--gki` | 标记为 GKI 通用内核(默认 LKM 模式) |
| `--ksu <main\|builtin>` | SukiSU 集成分支 |
| `--ksu-mode <y\|m>` | `y`=内置(非 GKI 默认),`m`=LKM 模块(GKI 默认) |
| `--kpm` | 启用 KPM(`CONFIG_KPM=y`) |
| `--debug-ksu` | 启用 `CONFIG_KSU_DEBUG` |
| `--clang <分支:目录>` | 覆盖 Clang 版本(如 `llvm-r522817:clang-r522817`) |
| `--gcc` | 强制 GCC 4.9 工具链(老内核) |
| `--jobs <n>` | 并行编译数(默认 nproc) |
| `--no-pack` | 只编译不打包 |
| `--resume` | 复用已有的 `work/kernel` 源码 |
| `--clean` | 开始前清空 `work/` 目录 |
| `--yes` | 跳过确认直接开始 |
| `--dry-run` | 演练模式: 只打印将执行的编译任务, 不下载/编译 |

示例:

```bash
bash build.sh --device alioth --version 1 --ksu main --yes          # 小米 K40, 全自动
bash build.sh --branch oneplus/SM8250_R_11.0 --ksu builtin          # 一加 8T OOS11, builtin 分支
bash build.sh --device gki-a15 --ksu-mode m --yes                   # 通用 GKI A15, 产出 kernelsu.ko
bash build.sh --repo https://github.com/xxx/kernel --branch main \
              --defconfig vendor/foo_defconfig --kver 5.15 --android 13 --gki
```

## 四、设备库(devices.conf)

已收录并通过 GitHub API 逐条核实的条目(**32 条**):

| 厂商 | 设备 | 内核版本 |
|---|---|---|
| 小米 | Redmi K40/POCO F3、K20 Pro、K20、K30 Pro、Mi 10/10 Pro、Note 10 Pro、Note 8/8T、POCO X3 NFC、K40 Pro、Mi 11、Note 11 Pro 5G | 4.14 / 4.19 / 5.4 |
| 一加 | 7/7 Pro/7T/7T Pro、8/8 Pro、8T/9R、9/9 Pro、9RT | 4.14 / 4.19 / 5.4 / 5.15 |
| 通用 GKI | Android 12 ~ 16(对应 KMI: 5.10 / 5.15 / 6.1 / 6.6 / 6.12) | GKI |

**添加自己的设备**:编辑 `devices.conf`,按格式追加一行(共 9 列,`|` 分隔):

```
设备ID|版本标签|设备显示名|内核仓库URL|分支名|内核版本|Android版本|GKI标志|defconfig提示
alioth|Android 11 · Linux 4.19|Redmi K40 / POCO F3|https://github.com/MiCode/Xiaomi_Kernel_OpenSource|alioth-r-oss|4.19|11|0|vendor/alioth_user_defconfig
```

- `GKI标志`:`1` = GKI 通用内核(默认 LKM 模式),`0` = 非 GKI(默认内置模式)
- `defconfig提示` 可留空(自动按设备 ID 探测),支持 glob(如 `vendor/kona*`)
- 分支名请务必到对应仓库确认存在(工具会在克隆失败时报错)

## 五、产物说明

产物输出到 `output/` 目录:

| 模式 | 产物 | 用法 |
|---|---|---|
| 内置(`CONFIG_KSU=y`,非 GKI 默认) | `SukiSU-Ultra_<设备>_<分支>_<版本>_<main\|builtin>.zip` | TWRP 等 Recovery 刷入(AnyKernel3 格式) |
| LKM(`CONFIG_KSU=m`,GKI 默认) | `SukiSU-Ultra_<设备>_<分支>_<版本>_<main\|builtin>_kernelsu.ko` | SukiSU 管理器 → 安装 → **使用本地 LKM 文件**(仅支持 `.ko`) |

> ⚠️ 刷机有风险:刷入前务必备份原 boot 分区(卡第一屏时恢复用);部分设备还需考虑 AVB/锁 BL 问题。

## 六、目录结构

```
sukisu-kernel-builder/
├── build.sh          # 主工具(全部逻辑)
├── devices.conf      # 设备库
├── README.md         # 本文档
├── work/             # 工作区(可整目录删除)
│   ├── toolchains/   # Clang / GCC 工具链(首次下载后复用)
│   ├── kernel/       # 内核源码 + 已集成的 SukiSU(KernelSU/)
│   ├── AnyKernel3/   # AK3 打包模板
│   └── ak3-pkg/      # 打包临时目录
├── output/           # 最终产物(zip / .ko)
└── build.log         # 编译日志
```

## 七、工作原理(对应教程章节)

1. **下载内核源码** — 按所选设备与版本克隆官方开源内核
2. **集成 SukiSU**(教程 *KernelSU 集成* 部分):优先运行官方 `setup.sh`(`curl ... | bash -s main|builtin`);失败时自动改用 GitHub 手动集成,等效操作:
   - 克隆 SukiSU 到 `KernelSU/`
   - 符号链接 `KernelSU/kernel → drivers/kernelsu`
   - `drivers/Makefile` 追加 `obj-$(CONFIG_KSU) += kernelsu/`
   - `drivers/Kconfig` 插入 `source "drivers/kernelsu/Kconfig"`
3. **内核配置**(教程 *KSU 配置* 部分),自动启用:
   - `main` 分支:`CONFIG_KSU=y|m` + `CONFIG_KPROBES=y` + `CONFIG_EXT4_FS=y`
   - 非 GKI 设备额外:`CONFIG_KALLSYMS=y` + `CONFIG_KALLSYMS_ALL=y`(教程安装页要求)
   - `builtin` 分支额外:ARM64 且 ≥4.19 尝试 `CONFIG_KSU_HACK_ARM64_BRANCH_LINK=y`(自动 hook),否则尝试 `CONFIG_KSU_TAMPER_SYSCALL_TABLE=y`;若该分支 Kconfig 无对应符号,会提示按教程手动打 hook 补丁
   - 可选:`--kpm`(KPM)、`--debug-ksu`
4. **编译** — 按 Android 版本自动选择 AOSP Clang 预编译分支(GKI 或 ≥5.10 用 `LLVM=1`;<4.14 或 `--gcc` 用 GCC 4.9)
5. **打包** — 内置模式用 AnyKernel3 打包 Image.gz + DTB(+DTBO);LKM 模式直接输出 `kernelsu.ko`

## 八、常见问题

| 问题 | 解决 |
|---|---|
| 依赖缺失 | 按脚本提示运行 apt 安装命令 |
| Clang 下载失败 | 网络问题;用 `--clang <分支:目录>` 换规格重试,工具链已下载部分会自动复用 |
| 官方 setup.sh 失败 | 工具会自动改用 GitHub 手动集成(等效操作),无需干预 |
| `CONFIG_KSU` 未生效 | 该内核缺 KPROBES/EXT4_FS 依赖;改用 `--ksu builtin`,或检查 `work/kernel/out/.config` |
| 4.14 老内核编译报错 | 改用 `--gcc`;或 `EXTRA_MAKE_ARGS="LLVM_IAS=1" bash build.sh ...` |
| 老内核脚本报 python2 缺失 | 需另装 python2(新发行版可考虑用 pyenv 或升级内核分支) |
| 想换编译参数 | 用环境变量 `EXTRA_MAKE_ARGS` 追加透传给 make 的参数 |
| 中断后重来 | 直接再跑一次 `bash build.sh --resume`(跳过源码/工具链下载);`--clean` 则全部重来 |
| GKI LKM 模块刷入后不生效 | 确认模块 KMI 与设备内核 KMI 一致(用设备对应的 GKI 分支重新编译) |

## 免责声明

本工具仅供学习与个人设备使用,编译、刷入内核存在风险,可能造成数据丢失或设备变砖,请自行承担。SukiSU-Ultra、AnyKernel3、各内核源码版权归各自作者所有。
