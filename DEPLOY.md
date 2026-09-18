# 部署流程（DeepSeek Harness 教程站 · tutorial.baimuyuan.online）

本文件是**本项目的实际部署手册**，所有路径、用户、命令都与线上环境一致，可直接复制执行。

---

## 0. 全貌

| 项目 | 值 |
|---|---|
| 访问地址 | `https://tutorial.baimuyuan.online/` （合集首页）<br>`https://tutorial.baimuyuan.online/deepseek-harness-tutorial/` （教程站） |
| 服务器 | 阿里云 ECS `123.56.2.125`，Nginx 1.18 |
| SSH 登录 | `admin`（**root 禁登录**），密钥 `~/.ssh/id_ed25519_penguin`，admin 有**免密 sudo** |
| 网站根目录 | `/www/wwwroot/tutorial.baimuyuan.online`（属主 `www-data`） |
| 教程站目录 | `/www/wwwroot/tutorial.baimuyuan.online/deepseek-harness-tutorial/` |
| 代码仓库 | `https://github.com/xiaoshancha/deepseek-harness-tutorial.git`（分支 `main`） |
| DNS / CDN | Cloudflare，A 记录 `tutorial` → 服务器 IP，**橙色云（Proxied）** |
| HTTPS | Let's Encrypt（certbot 自动签发 + 自动续期） |

### 两个站点、两份内容源

```
本地仓库                              服务器网站根
─────────────────────────────────    ─────────────────────────────────────────
home/index.html                  →   /www/wwwroot/tutorial.baimuyuan.online/index.html
.vitepress/dist/  (npm run build)→   /www/wwwroot/tutorial.baimuyuan.online/deepseek-harness-tutorial/
```

- **合集首页**：`home/index.html`，单文件、内联样式、无外部依赖（淡蓝赛博像素风），收录各教程的入口卡片。
- **教程站**：VitePress 从本目录的 Markdown 构建出的静态站，`base = '/deepseek-harness-tutorial/'`。

---

## 1. 一次性准备（已完成，仅备查）

> 这一节的内容**线上已经配好**，重装服务器时才需要。

1. **服务器基础**：安装 Nginx；确认 `admin` 用户可 SSH（root 已禁），并配置好免密 `sudo`。
2. **上传公钥**：把 `~/.ssh/id_ed25519_penguin.pub` 追加到服务器 `admin` 用户的 `~/.ssh/authorized_keys`。
3. **DNS**：Cloudflare 添加 `A` 记录 `tutorial` → `123.56.2.125`（橙色云）。
4. **Nginx 站点**：创建 `/etc/nginx/sites-available/tutorial.baimuyuan.online` 并软链到 `sites-enabled/`，
   `nginx -t && nginx -s reload`。核心规则（当前线上配置）：

   ```nginx
   server {
       server_name tutorial.baimuyuan.online;
       root /www/wwwroot/tutorial.baimuyuan.online;
       index index.html;

       location = /deepseek-harness-tutorial/ {        # 教程站首页
           try_files /deepseek-harness-tutorial/index.html =404;
       }
       location /deepseek-harness-tutorial/assets/ {   # 静态资源长缓存
           expires 7d;
           add_header Cache-Control "public, max-age=604800, immutable";
           try_files $uri =404;
       }
       location /deepseek-harness-tutorial/ {          # 章节页（cleanUrls：无 .html 也能命中）
           try_files $uri $uri.html $uri/ =404;
       }
       location = / {                                  # 站点根 → 合集首页
           try_files /index.html =404;
       }
       # 其余路径没有专门的 location，落到 Nginx 默认静态处理：文件不存在即 404

       listen 443 ssl;                                 # 以下 5 行由 certbot 写入
       ssl_certificate     /etc/letsencrypt/live/tutorial.baimuyuan.online/fullchain.pem;
       ssl_certificate_key /etc/letsencrypt/live/tutorial.baimuyuan.online/privkey.pem;
       include /etc/letsencrypt/options-ssl-nginx.conf;
       ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;
   }
   ```

5. **HTTPS 证书**：`sudo certbot --nginx -d tutorial.baimuyuan.online`（自动写入 443 + 80→443 跳转）。
6. **开启压缩**：创建 `/etc/nginx/conf.d/gzip.conf`（**关键性能项**，未开则每个章节 chunk 会以未压缩的大文件下发）：

   ```nginx
   gzip_vary on;
   gzip_proxied any;
   gzip_comp_level 6;
   gzip_min_length 1024;
   gzip_types text/plain text/css application/javascript application/json text/javascript application/xml application/xml+rss image/svg+xml font/woff2;
   ```

   > 注意：`gzip on;` 已在 `/etc/nginx/nginx.conf` 的 http 块里，**不要重复写**，否则 `nginx -t` 报 `directive is duplicate`。

7. **Cloudflare SSL 模式**：设为 **Full (strict)**（服务器已有有效证书）。若为 Flexible/关闭，回源会走 80/443 错配，容易出现 401/重定向异常。

---

## 2. 日常部署（推荐）：本地一键脚本

**适用**：改了文档或首页，想立刻上线。

**前置**：本地已 `npm install`；私钥 `~/.ssh/id_ed25519_penguin` 存在。

```bash
cd C:/Users/yq/Desktop/develop/学习/deepseek-harness-tutorials
bash deploy-local.sh
```

脚本 `deploy-local.sh` 做了 4 件事：

1. `npm run build` —— 构建教程站到 `.vitepress/dist/`
2. **上传到服务器中转目录** `/tmp/dsh-deploy/`（admin 对 `/tmp` 可写，无需 sudo）
3. **`sudo` 安装到网站目录** —— `sudo find … -mindepth 1 -delete` 清空旧文件 → `sudo cp` 覆盖 → `sudo chown -R www-data:www-data`
4. `curl` 校验首页与教程页返回码，最后打印访问地址

> **为什么要绕 `/tmp`？** 网站目录属主是 `www-data`，`admin` 对它**没有写权限**，直接 `scp` 会报 `Permission denied`。
> 正确姿势就是「传 `/tmp` → `sudo` 拷进去」，脚本已经封装好。

---

## 3. 日常部署（自动）：GitHub Actions

**适用**：推送到 `main` 后自动构建上线。

- 工作流文件：`.github/workflows/deploy.yml`
- 触发：`push` 到 `main`，或在仓库 **Actions → 部署到阿里云 (SSH) → Run workflow** 手动触发
- 流程：检出 → 装 Node 20 → `npm ci` → `npm run build` → 上传到 `/tmp/dsh-deploy/` → `sudo` 安装到网站目录

### 必须在仓库配置 Secrets

仓库 **Settings → Secrets and variables → Actions → New repository secret**，逐个添加：

| Secret | 值 |
|---|---|
| `SSH_HOST` | `123.56.2.125` |
| `SSH_USER` | `admin` |
| `SSH_PORT` | `22` |
| `SSH_PRIVATE_KEY` | `~/.ssh/id_ed25519_penguin` 的**完整私钥内容**（含 `-----BEGIN/END-----` 两行） |
| `SSH_SITE_ROOT` | `/www/wwwroot/tutorial.baimuyuan.online` |

> ✅ 上述 5 个 Secrets **已配置完成**，自动部署链路**已实跑验证成功**（运行 #9：构建、两次中转上传、sudo 安装全部 `success`）。
> 若将来 Secrets 缺失或私钥失效，工作流会在「上传教程站到中转目录」这步失败（报认证/权限错误）——重新按上表写入即可。
>
> **换密钥时**：本地生成新密钥对 → 新公钥追加到服务器 `admin` 的 `authorized_keys` → 用新私钥内容更新 `SSH_PRIVATE_KEY` Secret → 触发一次工作流验证 → 再删除旧公钥。

---

## 4. 手工部署（不用脚本）

```bash
cd C:/Users/yq/Desktop/develop/学习/deepseek-harness-tutorials
npm run build

KEY=~/.ssh/id_ed25519_penguin
R=/www/wwwroot/tutorial.baimuyuan.online

# 1) 传到中转目录
ssh -i $KEY admin@123.56.2.125 "mkdir -p /tmp/dsh-deploy/dist"
scp -i $KEY -r .vitepress/dist/* admin@123.56.2.125:/tmp/dsh-deploy/dist/
scp -i $KEY home/index.html     admin@123.56.2.125:/tmp/dsh-deploy/home-index.html

# 2) sudo 安装
ssh -i $KEY admin@123.56.2.125 "
  sudo mkdir -p $R/deepseek-harness-tutorial
  sudo find $R/deepseek-harness-tutorial -mindepth 1 -delete
  sudo cp -rf /tmp/dsh-deploy/dist/. $R/deepseek-harness-tutorial/
  sudo cp -f  /tmp/dsh-deploy/home-index.html $R/index.html
  sudo chown -R www-data:www-data $R/deepseek-harness-tutorial $R/index.html
"
```

---

## 5. 各类改动如何生效

| 改了什么 | 需要做什么 |
|---|---|
| `chapters/*.md`、`appendix-*.md`、`answers.md` | `npm run build` → 重新部署（脚本会做）|
| `.vitepress/config.mjs`（标题/侧边栏/base…）| 同上 |
| `.vitepress/theme/**`（加载动画等主题代码）| 同上 |
| `home/index.html`（合集首页）| 重新部署（脚本会一起上传）|
| Nginx 配置 | 改 `/etc/nginx/sites-available/tutorial.baimuyuan.online` → `sudo nginx -t && sudo nginx -s reload`（**不需要**重新构建）|
| 证书 | certbot 已自动续期；手动检查：`sudo certbot certificates` |

> 只推送到 GitHub 而**不**跑部署，线上不会变；部署只有两条路：本地脚本，或 Actions 工作流。

---

## 6. 部署后验证清单

```bash
D=https://tutorial.baimuyuan.online
curl -sS -o /dev/null -w "首页      %{http_code}\n" $D/
curl -sS -o /dev/null -w "教程首页  %{http_code}\n" $D/deepseek-harness-tutorial/
curl -sS -o /dev/null -w "章节页    %{http_code}\n" "$D/deepseek-harness-tutorial/chapters/01-从一条命令到一棵插件树"
curl -sS -o /dev/null -w "未知路径  %{http_code}\n" $D/no-such-path   # 期望 404
```

期望值：前三个 **200**，最后一个 **404**。
另外可检查资源是否压缩生效：响应头应含 `Content-Encoding: gzip`。

---

## 7. 常见坑（都踩过）

1. **SSH 只能用 `admin`，不是 `root`**：root 公钥登录被拒。所有部署命令都用 `admin`。
2. **`admin` 对网站目录无写权限**：目录属主 `www-data`。直接 `scp` 报 `Permission denied` → 必须「`/tmp` 中转 + `sudo cp` + `chown`」。
3. **`base` 必须与子路径一致**：`config.mjs` 里 `base: '/deepseek-harness-tutorial/'`，否则 JS/CSS 全 404。
4. **`cleanUrls: true`**：章节链接无 `.html`，Nginx 需 `try_files $uri $uri.html $uri/` 才能命中。
5. **JS/CSS 未压缩导致切页卡顿**：`gzip_types` 默认只含 `text/html`，JS 不压缩、每个章节 chunk 原样下发 → 需加 `/etc/nginx/conf.d/gzip.conf`（见第 1 节第 6 条）。
6. **公网 401**：曾因 Cloudflare 橙色云按 **Full** 回源到 443，而当时 `tutorial` 没有 443 配置，请求落到反代 WebDAV 的默认站点 → 401。给本域名签好证书、配上 443 后即正常；SSL 模式建议 **Full (strict)**。
7. **`www.baimuyuan.online` 不要动**：那是另一个站点（443 反代到本机 WebDAV 容器，返回 401 属正常）。改 Nginx 时只动 `tutorial.baimuyuan.online` 的配置。
8. **`DEPLOY.md` / `README.md` 不生成页面**：已在 `config.mjs` 用 `srcExclude` 排除。
9. **`gzip` 重复声明**：`nginx.conf` 已有 `gzip on;`，`conf.d` 里只加 `gzip_types` 等，别再写 `gzip on;`。
10. **缓存**：`assets/` 是 7 天 `immutable` 长缓存；HTML 不缓存。若改完看不到效果，先强制刷新；正常改内容会因文件名哈希变化而自动失效。

---

## 8. 回滚

- **内容回滚**：`git revert <commit>` 或 `git checkout <旧提交> -- .` 后重新部署。
- **服务器文件备份**：部署前如需稳妥，可先留存：

  ```bash
  ssh -i $KEY admin@123.56.2.125 "sudo tar czf /tmp/site-$(date +%F-%H%M).tgz -C /www/wwwroot tutorial.baimuyuan.online"
  ```

- **Nginx 回滚**：改动前 `sudo cp /etc/nginx/sites-available/tutorial.baimuyuan.online{,.bak}`，出错时还原再 `nginx -s reload`。

---

## 附：曾经考虑过的其他托管方式

Vercel / Netlify（推仓库后平台构建，零运维）、虚拟主机 FTP 上传（cPanel/宝塔）都可行，但本项目最终选择**自有阿里云服务器 + Nginx**，以便与服务器上已有的其他服务统一管理。若改用平台托管，记得把 `config.mjs` 的 `base` 改回 `'/'`。
