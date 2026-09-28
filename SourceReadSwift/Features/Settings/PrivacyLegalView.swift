import SwiftUI

/// App Store 审核准则（Guideline 5.1.1 / 5.1.2）合规隐私与法律条款中心
struct PrivacyLegalHubView: View {
    var body: some View {
        List {
            Section("合规与条款") {
                NavigationLink {
                    PrivacyPolicyDetailView()
                } label: {
                    Label("隐私政策 (Privacy Policy)", systemImage: "hand.raised.fill")
                }

                NavigationLink {
                    UserAgreementDetailView()
                } label: {
                    Label("用户服务协议 (Terms of Service)", systemImage: "doc.text.fill")
                }

                NavigationLink {
                    DisclaimerDetailView()
                } label: {
                    Label("技术与版权免责声明 (Disclaimer)", systemImage: "shield.lefthalf.filled")
                }

                NavigationLink {
                    OpenSourceLicensesDetailView()
                } label: {
                    Label("开源软件许可与致谢 (Licenses)", systemImage: "curlybraces")
                }
            }

            Section("核心隐私承诺") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "lock.shield.fill")
                            .foregroundStyle(AppTheme.accent)
                        Text("全本地化沙盒存储")
                            .font(.headline)
                    }
                    Text("「纸间」不设云端用户中心，不收集 IDFA 或设备唯一识别码。您的书架藏书、阅读进度、笔记书签及书源规则，100% 留存在当前设备的受保护沙盒内。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("合规与隐私")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// 隐私政策正文
struct PrivacyPolicyDetailView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("纸间（SourceRead）隐私政策")
                    .font(.title2.bold())

                Text("更新日期：2026年9月\n生效日期：2026年9月")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Divider()

                Group {
                    Text("一、我们如何收集与使用信息")
                        .font(.headline)
                    Text("1. 个人信息零收集：本应用不会向您索取姓名、手机号、电子邮件或身份证号等任何真实身份个人信息。应用无需注册或登录即可使用全部核心功能。")
                    Text("2. 设备标识符：我们不读取或追踪广告标识符（IDFA）、供应商标识符（IDFV）或 MAC 地址。")
                    Text("3. 用户内容与数据：您在应用中导入的电子书文件（TXT、EPUB）、自行添加的 JSON 书源、阅读偏好设置及阅读历史记录，均作为本地文件加密保存在 iOS 系统提供的应用沙盒中，不会向任何开发者服务器或第三方云存储回传。")
                }

                Group {
                    Text("二、网络权限与网络请求")
                        .font(.headline)
                    Text("1. 本地网络（Local Network）：当您开启「Web 写源与传输服务」时，应用会在局域网内开启轻量级 HTTP 服务供您在电脑浏览器调试书源。该传输仅在局域网两端直连完成，绝无中继转发。")
                    Text("2. 第三方书源网络请求：当您搜索书籍、获取目录或加载章节内容时，应用仅作为本地用户代理（User-Agent）向您所指定的公开书源域名发起常规 HTTP/HTTPS 请求。这些网络通信由您所配置的书源直接决定，本应用不对目标源站的数据传输进行中间人拦截或二次转存。")
                }

                Group {
                    Text("三、第三方 SDK 与追踪器说明")
                        .font(.headline)
                    Text("本应用恪守纯粹工具原则，未集成任何商业广告 SDK、行为统计 SDK 或跨应用追踪组件（Zero Analytics & Zero Ad Trackers），杜绝一切潜在隐私泄漏风险。")
                }

                Group {
                    Text("四、未成年人保护")
                        .font(.headline)
                    Text("本应用不主动收集未成年人的任何个人数据。若监护人发现未成年人自行导入了不合规内容，可直接在设备端清空书架或删除应用。")
                }

                Group {
                    Text("五、隐私政策的更新")
                        .font(.headline)
                    Text("我们可能会根据法规变动或功能演进适时修订本政策。最新版本将始终在应用设置内展示。如有疑问，可通过关于页面的反馈通道与开发者取得联系。")
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("隐私政策")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// 用户服务协议正文
struct UserAgreementDetailView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("纸间（SourceRead）用户服务协议")
                    .font(.title2.bold())

                Text("更新日期：2026年9月")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Divider()

                Group {
                    Text("一、导言与服务说明")
                        .font(.headline)
                    Text("欢迎使用「纸间」。本协议是您与纸间开发者之间就下载、安装及使用本应用所订立的具有法律效力的协议。通过下载、安装或使用本应用，即表示您同意接受本协议的全部条款。")
                }

                Group {
                    Text("二、软件性质与功能边界")
                        .font(.headline)
                    Text("1. 本应用是一款定位于本地电子书阅读与自定义书源规则解析的客户端排版工具。")
                    Text("2. 本应用本身不提供任何在线阅读服务器，不编辑、不修改、不精选任何第三方书籍内容。应用内的所有在线内容检索与呈现均取决于用户自主配置的书源脚本。")
                }

                Group {
                    Text("三、用户使用规范与合规义务")
                        .font(.headline)
                    Text("1. 用户在使用本应用时，应当遵守中华人民共和国及用户所在地适用的法律法规，不得利用本应用从事侵犯他人著作权、传播违规有害信息等违法行为。")
                    Text("2. 用户自行导入、制作或分享的书源文件，应当确保来源合法合规，不得侵犯任何第三方的合法权益。")
                }

                Group {
                    Text("四、知识产权声明")
                        .font(.headline)
                    Text("本应用的软件著作权、界面交互设计、底层排版引擎算法及图标视觉素材均归开发者合法所有。未经授权，任何个人或组织不得擅自反编译、破解或用于商业牟利。")
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("用户协议")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// 技术与版权免责声明
struct DisclaimerDetailView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("技术与版权免责声明")
                    .font(.title2.bold())

                Divider()

                Group {
                    Text("一、内容免责")
                        .font(.headline)
                    Text("1. 「纸间」仅作为本地中立阅读排版容器与规则执行引擎存在，不向用户提供任何受版权保护的数字出版物。")
                    Text("2. 任何通过第三方书源解析所呈现的图书文本、封面、插图及作者信息，其知识产权均完全属于原权利人或原发布平台。")
                    Text("3. 若任何权利方认为用户自行导入的特定书源涉嫌侵犯其合法权益，请直接与相关目标网站或书源作者联系，或向我们提供权属凭据以在本地规则检测库中予以阻断。")
                }

                Group {
                    Text("二、服务可用性免责")
                        .font(.headline)
                    Text("由于网络环境的复杂性及第三方源站的不可预测性，本应用无法保证所有外部书源链接的长期有效性、速度及准确性。因源站变动、服务器下线等导致的解析失败，属于第三方网络服务的固有局限，本应用不承担连带责任。")
                }

                Group {
                    Text("三、数据安全免责")
                        .font(.headline)
                    Text("本应用数据均存储于用户设备沙盒内。建议用户定期使用应用内的「导出完整数据」功能对个人书架与书源进行离线备份。因设备硬件损坏、系统崩溃或用户自行卸载应用造成的数据灭失，应用开发者无法提供远端恢复服务。")
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("免责声明")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// 开源软件许可与致谢
struct OpenSourceLicensesDetailView: View {
    var body: some View {
        List {
            Section("开源致敬") {
                Text("「纸间」的诞生离不开全球优秀开源社区的卓越贡献。在此向以下杰出的开源项目及贡献者致以崇高的敬意：")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("SwiftSoup") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("SwiftSoup (HTML Parser)")
                        .font(.subheadline.bold())
                    Text("License: MIT License\nCopyright (c) Nabil Chatbi")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("ZIPFoundation") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("ZIPFoundation (ZIP Archive Processing)")
                        .font(.subheadline.bold())
                    Text("License: MIT License\nCopyright (c) Thomas Rasch")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("CryptoSwift") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("CryptoSwift (Cryptography Engine)")
                        .font(.subheadline.bold())
                    Text("License: Custom / Apache 2.0 compatible\nCopyright (c) Marcin Krzyzanowski")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Legado & 源阅读社区") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("开源阅读 (Legado) & 源阅读")
                        .font(.subheadline.bold())
                    Text("感谢开源阅读团队建立的通用开放书源规则生态规范，赋能亿万读者自主选择文字的权利。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("开源许可")
        .navigationBarTitleDisplayMode(.inline)
    }
}
