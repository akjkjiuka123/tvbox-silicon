// Site copy for every supported language.

export const LANGS = ["en","ja","ko","zh-Hant"] as const;
export type Lang = (typeof LANGS)[number];

export type TextKey =
  | "brand"
  | "c.live.b"
  | "c.live.t"
  | "c.search.b"
  | "c.search.t"
  | "c.site.b"
  | "c.site.t"
  | "cta.l1"
  | "cta.l2"
  | "cta.sub"
  | "faq.l1"
  | "faq.l2"
  | "footer.disclaimer"
  | "footer.lang"
  | "footer.source"
  | "g.devices.b"
  | "g.devices.t"
  | "g.dl.b"
  | "g.dl.t"
  | "g.lang.b"
  | "g.lang.t"
  | "g.play.b"
  | "g.play.t"
  | "g.private.b"
  | "g.private.t"
  | "g.sub.b"
  | "g.sub.t"
  | "hero.film"
  | "hero.l1"
  | "hero.l2"
  | "hero.meta"
  | "hero.more"
  | "hero.sub"
  | "meta.description"
  | "meta.title"
  | "more.l1"
  | "more.l2"
  | "nav.faq"
  | "nav.features"
  | "q1.a"
  | "q1.q"
  | "q2.a"
  | "q2.q"
  | "q3.a"
  | "q3.q"
  | "q4.a"
  | "q4.q"
  | "q5.a"
  | "q5.q"
  | "q6.a"
  | "q6.q"
  | "sec.l1"
  | "sec.l2"
  | "sec.sub"
  | "soon"
  | "new"
  | "dl.mac"
  | "dl.req";

export interface Locale {
  name: string;
  chips: string[];
  text: Record<TextKey, string>;
}

export const LOCALES: Record<Lang, Locale> = {
  "en": {
    name: "English",
    chips: ["Watch Now","Live TV guide","Global search","Favorites","JSON sources","M3U & TXT playlists","HLS","Picture in Picture on Mac","No account"],
    text: {
      "brand": "Yingxia",
      "c.live.b": "Bring M3U or TXT playlists. Browse by group, search channels, and keep your favorites close.",
      "c.live.t": "Live TV, laid out like a guide.",
      "c.search.b": "One query runs across every source in your subscription. Results appear as they arrive.",
      "c.search.t": "Search everything at once.",
      "c.site.b": "Browse the categories and pages of any source with nothing but the Siri Remote.",
      "c.site.t": "Every source gets its own shelf.",
      "cta.l1": "Ready",
      "cta.l2": "for every screen.",
      "cta.sub": "Yingxia for Mac is available now. The Apple TV, iPhone and iPad versions are in public beta on TestFlight.",
      "faq.l1": "Questions,",
      "faq.l2": "answered.",
      "footer.disclaimer": "Yingxia does not host, provide or endorse any media content. Apple TV, iPhone, iPad and Mac are trademarks of Apple Inc. This project is not affiliated with Apple.",
      "footer.lang": "Language",
      "footer.source": "Open source on GitHub",
      "g.devices.b": "Apple TV, iPhone, iPad and Mac share the same subscriptions and favorites.",
      "g.devices.t": "Every Apple screen",
      "g.dl.t": "Watch offline",
      "g.dl.b": "Download episodes and movies to watch without a connection, on Apple TV, iPhone, iPad and Mac.",
      "g.lang.b": "English, Japanese, Traditional and Simplified Chinese, following your system setting.",
      "g.lang.t": "Speaks your language",
      "g.play.b": "AVPlayer with HLS, clear error screens with Retry, and Picture in Picture on Mac.",
      "g.play.t": "Native playback",
      "g.private.b": "No account and no tracking. Subscriptions and history stay on your device; only anonymous error reports are sent, and you can turn them off.",
      "g.private.t": "Private by design",
      "g.sub.b": "Import TVBox JSON subscriptions by URL, several at once, merged into one list of sources. A failed refresh never wipes the last working copy.",
      "g.sub.t": "Your subscriptions, kept safe",
      "hero.film": "Watch the intro film",
      "hero.l1": "All your sources.",
      "hero.l2": "One big screen.",
      "hero.meta": "Preview · tvOS 17 · iOS 17 · macOS 15",
      "hero.more": "See how it works",
      "hero.sub": "Yingxia plays your TVBox subscriptions natively on Apple TV, iPhone, iPad and Mac: live channels, on-demand catalogs, and one search across every source.",
      "meta.description": "Free, native TVBox player for Apple TV, iPhone, iPad and Mac. Live channels, on-demand catalogs and one search across all your sources.",
      "meta.title": "Yingxia — TVBox player for Apple TV, iPhone, iPad and Mac",
      "more.l1": "The details",
      "more.l2": "that matter.",
      "nav.faq": "FAQ",
      "nav.features": "Features",
      "q1.a": "Yingxia is a native TVBox client written in SwiftUI. It reads TVBox JSON subscriptions and plays their videos and live channels with Apple’s AVPlayer.",
      "q1.q": "What is Yingxia?",
      "q2.a": "No. Yingxia is a player and shows only what the subscriptions you add provide. You are responsible for using sources you have the right to access.",
      "q2.q": "Does it come with any videos or channels?",
      "q3.a": "Apple TV with tvOS 17 or later, iPhone and iPad with iOS 17 or later, and Mac with macOS 15 or later. The Mac version also has a separate player window with Picture in Picture.",
      "q3.q": "Which devices does it run on?",
      "q4.a": "TVBox JSON subscriptions with standard JSON APIs, and M3U and TXT live playlists. Support varies by source, and upstream servers sometimes change or go offline.",
      "q4.q": "Which sources work?",
      "q5.a": "Only anonymous error reports, so bugs get fixed: the error text with web addresses cut to the server name, the app and system versions, and a random ID. You can turn them off in Settings. There is no account, and subscriptions, favorites and history stay on your device.",
      "q5.q": "Does it collect my data?",
      "q6.a": "The Mac version is a free download, signed and notarized by Apple. The Apple TV, iPhone and iPad versions are free public betas: join them in TestFlight, or sideload the IPA with cider or an app like Impactor. See the install guide above.",
      "q6.q": "When can I get it?",
      "sec.l1": "Everything TVBox does.",
      "sec.l2": "Rebuilt natively.",
      "sec.sub": "Written in SwiftUI and played through AVKit. No web views, no ported Android screens.",
      "dl.mac": "Download",
      "dl.req": "For Mac, iPhone, iPad and Apple TV · Free",
      "soon": "Coming soon",
      "new": "New",
    },
  },
  "ja": {
    name: "日本語",
    chips: ["今すぐ観る","ライブ番組ガイド","横断検索","お気に入り","JSON ソース","M3U・TXT プレイリスト","HLS","Mac でピクチャ・イン・ピクチャ","アカウント不要"],
    text: {
      "brand": "映匣",
      "c.live.b": "M3U や TXT のプレイリストを読み込み、グループで絞り込み、チャンネルを検索し、お気に入りを手元に。",
      "c.live.t": "ライブ TV を、番組ガイドのように。",
      "c.search.b": "ひとつのキーワードで、配信設定内のすべてのソースを検索。結果は届いた順に表示されます。",
      "c.search.t": "すべてを一度に検索。",
      "c.site.b": "どのソースのカテゴリーやページも、Siri Remote だけで閲覧できます。",
      "c.site.t": "ソースごとに、専用の棚を。",
      "cta.l1": "どの画面でも、",
      "cta.l2": "すぐに。",
      "cta.sub": "映匣の Mac 版を公開しました。Apple TV、iPhone、iPad 版は TestFlight でパブリックベータを公開中です。",
      "faq.l1": "よくある",
      "faq.l2": "質問。",
      "footer.disclaimer": "映匣はいかなるメディアコンテンツもホスト・提供・推奨しません。Apple TV、iPhone、iPad、Mac は Apple Inc. の商標です。本プロジェクトは Apple とは関係ありません。",
      "footer.lang": "言語",
      "footer.source": "GitHub でオープンソース公開中",
      "g.devices.b": "Apple TV、iPhone、iPad、Mac で同じ配信設定とお気に入りを使えます。",
      "g.devices.t": "すべての Apple の画面で",
      "g.dl.t": "オフラインで観る",
      "g.dl.b": "エピソードや映画をダウンロードして、接続なしで観られます。Apple TV、iPhone、iPad、Mac で。",
      "g.lang.b": "英語、日本語、繁体字・簡体字中国語に対応し、システム設定に従います。",
      "g.lang.t": "あなたの言語で",
      "g.play.b": "HLS 対応の AVPlayer、再試行できるわかりやすいエラー画面、Mac ではピクチャ・イン・ピクチャ。",
      "g.play.t": "ネイティブ再生",
      "g.private.b": "アカウント不要、トラッキングなし。配信設定や履歴はデバイス内に保存され、送信されるのは匿名のエラーレポートだけで、オフにもできます。",
      "g.private.t": "プライバシー重視",
      "g.sub.b": "TVBox の JSON 配信設定を URL から読み込み。複数をまとめて 1 つのソース一覧に。更新に失敗しても、最後に動いていた内容は消えません。",
      "g.sub.t": "配信設定を安全に保持",
      "hero.film": "紹介動画を見る",
      "hero.l1": "すべてのソースを、",
      "hero.l2": "ひとつの大画面で。",
      "hero.meta": "プレビュー · tvOS 17 · iOS 17 · macOS 15",
      "hero.more": "仕組みを見る",
      "hero.sub": "映匣は TVBox の配信設定を Apple TV、iPhone、iPad、Mac でネイティブに再生します。ライブチャンネル、オンデマンド作品、そしてすべてのソースを横断する検索。",
      "meta.description": "Apple TV、iPhone、iPad、Mac 向けの無料ネイティブ TVBox プレーヤー。ライブチャンネル、オンデマンド作品、すべてのソースを横断する検索。",
      "meta.title": "映匣 — Apple TV・iPhone・iPad・Mac 向け TVBox プレーヤー",
      "more.l1": "大切なことを、",
      "more.l2": "細部まで。",
      "nav.faq": "よくある質問",
      "nav.features": "機能",
      "q1.a": "SwiftUI で書かれたネイティブの TVBox クライアントです。TVBox の JSON 配信設定を読み込み、動画やライブチャンネルを Apple の AVPlayer で再生します。",
      "q1.q": "映匣とは？",
      "q2.a": "いいえ。映匣はプレーヤーで、追加した配信設定が提供する内容だけを表示します。利用する権利のあるソースを使うのはユーザーの責任です。",
      "q2.q": "動画やチャンネルは含まれていますか？",
      "q3.a": "tvOS 17 以降の Apple TV、iOS 17 以降の iPhone と iPad、macOS 15 以降の Mac です。Mac 版にはピクチャ・イン・ピクチャ対応の独立したプレーヤーウインドウもあります。",
      "q3.q": "どのデバイスで使えますか？",
      "q4.a": "標準の JSON API を使う TVBox の配信設定と、M3U・TXT のライブプレイリストです。対応状況はソースによって異なり、上流のサーバーが変更・停止することもあります。",
      "q4.q": "どのソースが使えますか？",
      "q5.a": "不具合修正のための匿名エラーレポートだけです。内容はエラー文（URL はサーバー名のみ）、アプリと OS のバージョン、ランダムな ID で、設定でオフにできます。アカウントはなく、配信設定、お気に入り、履歴はデバイス内にのみ保存されます。",
      "q5.q": "データは収集されますか？",
      "q6.a": "Mac 版は無料でダウンロードできます（Apple による署名・公証済み）。Apple TV、iPhone、iPad 版は無料のパブリックベータで、TestFlight から参加できます。cider などのツールで IPA をサイドロードすることもできます。上のインストール手順をご覧ください。",
      "q6.q": "いつ使えますか？",
      "sec.l1": "TVBox のすべてを、",
      "sec.l2": "ネイティブに。",
      "sec.sub": "SwiftUI で書かれ、AVKit で再生。Web ビューも、Android 画面の移植もありません。",
      "dl.mac": "ダウンロード",
      "dl.req": "Mac・iPhone・iPad・Apple TV 対応 · 無料",
      "soon": "近日公開",
      "new": "新機能",
    },
  },
  "ko": {
    name: "한국어",
    chips: ["지금 보기","실시간 TV 가이드","통합 검색","즐겨찾기","JSON 소스","M3U·TXT 재생 목록","HLS","Mac에서 PIP","계정 불필요"],
    text: {
      "brand": "Yingxia",
      "c.live.b": "M3U 또는 TXT 재생 목록을 불러와 그룹별로 탐색하고, 채널을 검색하고, 즐겨찾기를 가까이 두세요.",
      "c.live.t": "실시간 TV를 편성표처럼.",
      "c.search.b": "검색어 하나로 구독의 모든 소스를 검색합니다. 결과는 도착하는 대로 표시됩니다.",
      "c.search.t": "모든 소스를 한 번에 검색.",
      "c.site.b": "어떤 소스든 카테고리와 페이지를 Siri Remote만으로 둘러볼 수 있습니다.",
      "c.site.t": "소스마다 자신만의 진열대.",
      "cta.l1": "모든 화면에서",
      "cta.l2": "지금 바로.",
      "cta.sub": "Yingxia Mac 버전이 출시되었습니다. Apple TV, iPhone, iPad 버전은 TestFlight에서 공개 베타로 만나 보세요.",
      "faq.l1": "자주 묻는",
      "faq.l2": "질문.",
      "footer.disclaimer": "Yingxia는 어떠한 미디어 콘텐츠도 호스팅, 제공 또는 보증하지 않습니다. Apple TV, iPhone, iPad, Mac은 Apple Inc.의 상표입니다. 이 프로젝트는 Apple과 관련이 없습니다.",
      "footer.lang": "언어",
      "footer.source": "GitHub에서 오픈 소스로 공개",
      "g.devices.b": "Apple TV, iPhone, iPad, Mac에서 같은 구독과 즐겨찾기를 사용합니다.",
      "g.devices.t": "모든 Apple 화면에서",
      "g.dl.t": "오프라인 시청",
      "g.dl.b": "에피소드와 영화를 다운로드해 연결 없이 볼 수 있습니다. Apple TV, iPhone, iPad, Mac 모두에서.",
      "g.lang.b": "영어, 일본어, 번체·간체 중국어를 지원하며 시스템 설정을 따릅니다.",
      "g.lang.t": "여러 언어 지원",
      "g.play.b": "HLS를 지원하는 AVPlayer, 재시도할 수 있는 명확한 오류 화면, Mac의 PIP.",
      "g.play.t": "네이티브 재생",
      "g.private.b": "계정도 추적도 없습니다. 구독과 기록은 기기에 남고, 익명 오류 보고서만 전송되며 끌 수도 있습니다.",
      "g.private.t": "프라이버시 중심 설계",
      "g.sub.b": "TVBox JSON 구독을 URL로 가져오세요. 여러 개를 하나의 소스 목록으로 합칩니다. 새로 고침에 실패해도 마지막으로 작동한 내용은 사라지지 않습니다.",
      "g.sub.t": "구독을 안전하게",
      "hero.film": "소개 영상 보기",
      "hero.l1": "모든 소스를,",
      "hero.l2": "하나의 큰 화면에서.",
      "hero.meta": "프리뷰 · tvOS 17 · iOS 17 · macOS 15",
      "hero.more": "작동 방식 보기",
      "hero.sub": "Yingxia는 TVBox 구독을 Apple TV, iPhone, iPad, Mac에서 네이티브로 재생합니다. 실시간 채널, 주문형 콘텐츠, 그리고 모든 소스를 아우르는 하나의 검색.",
      "meta.description": "Apple TV, iPhone, iPad, Mac을 위한 무료 네이티브 TVBox 플레이어. 실시간 채널, 주문형 콘텐츠, 모든 소스를 아우르는 하나의 검색.",
      "meta.title": "Yingxia — Apple TV·iPhone·iPad·Mac용 TVBox 플레이어",
      "more.l1": "중요한 것은",
      "more.l2": "디테일에.",
      "nav.faq": "FAQ",
      "nav.features": "기능",
      "q1.a": "SwiftUI로 작성된 네이티브 TVBox 클라이언트입니다. TVBox JSON 구독을 읽어 동영상과 실시간 채널을 Apple의 AVPlayer로 재생합니다.",
      "q1.q": "Yingxia는 무엇인가요?",
      "q2.a": "아니요. Yingxia는 플레이어이며, 직접 추가한 구독이 제공하는 내용만 보여 줍니다. 이용 권한이 있는 소스를 사용하는 것은 사용자의 책임입니다.",
      "q2.q": "동영상이나 채널이 포함되어 있나요?",
      "q3.a": "tvOS 17 이상의 Apple TV, iOS 17 이상의 iPhone과 iPad, macOS 15 이상의 Mac입니다. Mac 버전에는 PIP를 지원하는 별도의 플레이어 창도 있습니다.",
      "q3.q": "어떤 기기에서 사용할 수 있나요?",
      "q4.a": "표준 JSON API를 쓰는 TVBox 구독과 M3U·TXT 실시간 재생 목록입니다. 지원 여부는 소스에 따라 다르며, 원본 서버가 바뀌거나 중단될 수도 있습니다.",
      "q4.q": "어떤 소스를 쓸 수 있나요?",
      "q5.a": "버그 수정을 위한 익명 오류 보고서만 보냅니다. 오류 내용(웹 주소는 서버 이름만), 앱과 시스템 버전, 임의의 ID가 포함되며 설정에서 끌 수 있습니다. 계정은 없고 구독, 즐겨찾기, 기록은 기기에만 저장됩니다.",
      "q5.q": "내 데이터를 수집하나요?",
      "q6.a": "Mac 버전은 지금 무료로 다운로드할 수 있으며 Apple의 서명과 공증을 받았습니다. Apple TV, iPhone, iPad 버전은 무료 공개 베타로, TestFlight에서 참여할 수 있습니다. cider 같은 도구로 IPA를 사이드로드할 수도 있습니다. 위의 설치 안내를 참고하세요.",
      "q6.q": "언제 사용할 수 있나요?",
      "sec.l1": "TVBox의 모든 것을,",
      "sec.l2": "네이티브로.",
      "sec.sub": "SwiftUI로 작성하고 AVKit으로 재생합니다. 웹 뷰도, Android 화면 이식도 없습니다.",
      "dl.mac": "다운로드",
      "dl.req": "Mac·iPhone·iPad·Apple TV 지원 · 무료",
      "soon": "출시 예정",
      "new": "새로운 기능",
    },
  },
  "zh-Hant": {
    name: "繁體中文",
    chips: ["立即觀看","直播頻道指南","全域搜尋","收藏","JSON 片源","M3U、TXT 播放清單","HLS","Mac 子母畫面","免帳號"],
    text: {
      "brand": "映匣",
      "c.live.b": "匯入 M3U 或 TXT 播放清單，依分組瀏覽、搜尋頻道，常看的加入收藏。",
      "c.live.t": "直播電視，像節目表一樣清楚。",
      "c.search.b": "一個關鍵字就能搜尋訂閱中的所有片源，結果隨到隨顯示。",
      "c.search.t": "一次搜尋所有片源。",
      "c.site.b": "只用 Siri Remote 就能瀏覽任何片源的分類與頁面。",
      "c.site.t": "每個片源，都有自己的片架。",
      "cta.l1": "每一塊螢幕，",
      "cta.l2": "現在就能用。",
      "cta.sub": "映匣 Mac 版現已推出，Apple TV、iPhone 與 iPad 版則在 TestFlight 公開測試中。",
      "faq.l1": "常見",
      "faq.l2": "問題。",
      "footer.disclaimer": "映匣不託管、提供或認可任何媒體內容。Apple TV、iPhone、iPad 與 Mac 是 Apple Inc. 的商標。本專案與 Apple 無關。",
      "footer.lang": "語言",
      "footer.source": "在 GitHub 開放原始碼",
      "g.devices.b": "Apple TV、iPhone、iPad 與 Mac 共用同樣的訂閱與收藏。",
      "g.devices.t": "所有 Apple 螢幕",
      "g.dl.t": "離線觀看",
      "g.dl.b": "下載劇集與電影，沒有網路也能看。Apple TV、iPhone、iPad 與 Mac 都支援。",
      "g.lang.b": "支援英文、日文、繁體與簡體中文，跟隨系統語言設定。",
      "g.lang.t": "說你的語言",
      "g.play.b": "支援 HLS 的 AVPlayer、可一鍵重試的清楚錯誤畫面，Mac 上還有子母畫面。",
      "g.play.t": "原生播放",
      "g.private.b": "無需帳號、不追蹤。訂閱與紀錄都留在你的裝置上，只會傳送匿名錯誤報告，也可以關閉。",
      "g.private.t": "隱私至上",
      "g.sub.b": "透過網址匯入 TVBox JSON 訂閱，可同時使用多個，片源合併成一個清單。更新失敗也不會清除最後一次可用的內容。",
      "g.sub.t": "訂閱妥善保存",
      "hero.film": "觀看介紹影片",
      "hero.l1": "所有片源，",
      "hero.l2": "盡在大螢幕。",
      "hero.meta": "預覽 · tvOS 17 · iOS 17 · macOS 15",
      "hero.more": "看看怎麼用",
      "hero.sub": "映匣在 Apple TV、iPhone、iPad 與 Mac 上原生播放你的 TVBox 訂閱：直播頻道、隨選影片，以及橫跨所有片源的一次搜尋。",
      "meta.description": "為 Apple TV、iPhone、iPad 與 Mac 打造的免費原生 TVBox 播放器：直播頻道、隨選影片，以及橫跨所有片源的一次搜尋。",
      "meta.title": "映匣 — Apple TV、iPhone、iPad 與 Mac 的 TVBox 播放器",
      "more.l1": "重要的，",
      "more.l2": "都在細節裡。",
      "nav.faq": "常見問題",
      "nav.features": "功能",
      "q1.a": "以 SwiftUI 撰寫的原生 TVBox 用戶端。它讀取 TVBox JSON 訂閱，並以 Apple 的 AVPlayer 播放影片與直播頻道。",
      "q1.q": "映匣是什麼？",
      "q2.a": "沒有。映匣是一款播放器，只會顯示你加入的訂閱所提供的內容。請確保你有權使用所選的片源。",
      "q2.q": "有內建任何影片或頻道嗎？",
      "q3.a": "tvOS 17 以上的 Apple TV、iOS 17 以上的 iPhone 與 iPad，以及 macOS 15 以上的 Mac。Mac 版另有支援子母畫面的獨立播放視窗。",
      "q3.q": "支援哪些裝置？",
      "q4.a": "使用標準 JSON API 的 TVBox 訂閱，以及 M3U 與 TXT 直播清單。支援程度依片源而異，上游伺服器也可能變動或下線。",
      "q4.q": "支援哪些片源？",
      "q5.a": "只會傳送匿名錯誤報告，用來修正問題：錯誤內容（網址只保留伺服器名稱）、App 與系統版本，以及一組隨機 ID，可在設定中關閉。沒有帳號，訂閱、收藏與紀錄只存在你的裝置上。",
      "q5.q": "會收集我的資料嗎？",
      "q6.a": "Mac 版現在即可免費下載，並已通過 Apple 簽署與公證。Apple TV、iPhone 與 iPad 版是免費的公開測試版，可透過 TestFlight 加入；也可以用 cider 等工具側載 IPA。請參考上方的安裝說明。",
      "q6.q": "什麼時候可以用？",
      "sec.l1": "TVBox 的一切，",
      "sec.l2": "原生重建。",
      "sec.sub": "以 SwiftUI 撰寫、透過 AVKit 播放。沒有網頁視圖，也不是移植的 Android 畫面。",
      "dl.mac": "下載",
      "dl.req": "支援 Mac、iPhone、iPad 與 Apple TV · 免費",
      "soon": "即將推出",
      "new": "新功能",
    },
  },
};
