"""Captions and badge text of the store screenshots, one dict per app language.

Written by hand per language, not machine translated. Each screen has an
eyebrow, a headline ("\\n" marks the line break on phones and tablets) and a
sub line; CHIPS holds the two floating badges. "{self}" is the device the
screenshot was taken on (frame.py SELF). Facts the copy relies on, checked
2026-10-07: links are end-to-end encrypted, up to 100 GB (GET /api/v1/config
transfer_max_file_size_free), and the app's links expire after 24 hours;
QR Beam needs no network; Rooms join by a 4-character code; no account exists.
Never put a transfer speed or a time on a badge.
"""

# badge pictogram and colour per screen: (first badge), (second badge)
SCREENS = {
    "share": [("phone", "blue"), ("check", "green")],
    "link": [("link", "blue"), ("download", "orange")],
    "qr_beam": [("qr", "sky"), ("camera", "blue")],
    "rooms": [("users", "blue"), ("check", "green")],
    "settings": [("lock", "blue"), ("noaccount", "green")],
}

CAPTIONS: dict[str, dict[str, tuple[str, str, str]]] = {
    "en": {
        "share": ("CROSS-PLATFORM TRANSFER", "Send anything.\nTo any device.", "Instantly, over your own Wi-Fi. Free, no account."),
        "link": ("SECURE LINK", "Send to anyone.\nNo app needed.", "An encrypted link up to 100 GB, opened in any browser."),
        "qr_beam": ("QR BEAM", "No network?\nScreen to camera.", "No Wi-Fi, hotspot or Bluetooth. Best for text, keys and small files."),
        "rooms": ("ROOMS", "One short code.\nEveryone in.", "Share with a group. Everyone grabs what they need."),
        "settings": ("PRIVATE BY DESIGN", "End-to-end\nencrypted.", "No sign-up, no email, no profile. Ever."),
    },
    "id": {
        "share": ("TRANSFER LINTAS PERANGKAT", "Kirim apa saja.\nKe perangkat apa pun.", "Langsung lewat Wi-Fi sendiri. Gratis, tanpa akun."),
        "link": ("TAUTAN AMAN", "Kirim ke siapa saja.\nTanpa perlu aplikasi.", "Tautan terenkripsi hingga 100 GB, dibuka di browser apa pun."),
        "qr_beam": ("QR BEAM", "Tanpa jaringan?\nLayar ke kamera.", "Tanpa Wi-Fi, hotspot, atau Bluetooth. Cocok untuk teks, kunci, dan file kecil."),
        "rooms": ("RUANGAN", "Satu kode pendek.\nSemua masuk.", "Berbagi dengan grup. Tiap orang ambil yang dibutuhkan."),
        "settings": ("PRIVAT SEJAK AWAL", "Terenkripsi\nend-to-end.", "Tanpa daftar, tanpa email, tanpa profil. Selamanya."),
    },
    "de": {
        "share": ("PLATTFORMÜBERGREIFEND", "Alles senden.\nAn jedes Gerät.", "Sofort über das eigene WLAN. Kostenlos, ohne Konto."),
        "link": ("SICHERER LINK", "An alle senden.\nOhne App.", "Ein verschlüsselter Link bis 100 GB, öffnet in jedem Browser."),
        "qr_beam": ("QR BEAM", "Kein Netz?\nBildschirm zu Kamera.", "Ohne WLAN, Hotspot oder Bluetooth. Ideal für Text, Schlüssel und kleine Dateien."),
        "rooms": ("RÄUME", "Ein kurzer Code.\nAlle sind drin.", "Mit einer Gruppe teilen. Jeder holt sich, was er braucht."),
        "settings": ("PRIVAT VON GRUND AUF", "Ende-zu-Ende\nverschlüsselt.", "Keine Anmeldung, keine E-Mail, kein Profil. Niemals."),
    },
    "fr": {
        "share": ("TRANSFERT MULTIPLATEFORME", "Envoyez tout.\nÀ tout appareil.", "Instantanément, via votre Wi-Fi. Gratuit, sans compte."),
        "link": ("LIEN SÉCURISÉ", "Envoyez à tous.\nSans application.", "Un lien chiffré jusqu'à 100\u00a0Go, ouvert dans n'importe quel navigateur."),
        "qr_beam": ("QR BEAM", "Pas de réseau\u00a0?\nDe l'écran à la caméra.", "Ni Wi-Fi, ni partage de connexion, ni Bluetooth. Idéal pour du texte, des clés et de petits fichiers."),
        "rooms": ("SALONS", "Un code court.\nTout le monde entre.", "Partagez en groupe. Chacun prend ce dont il a besoin."),
        "settings": ("PRIVÉ PAR CONCEPTION", "Chiffré de\nbout en bout.", "Ni inscription, ni e-mail, ni profil. Jamais."),
    },
    "es": {
        "share": ("TRANSFERENCIA MULTIPLATAFORMA", "Envía lo que sea.\nA cualquier dispositivo.", "Al instante, por tu propio Wi-Fi. Gratis y sin cuenta."),
        "link": ("ENLACE SEGURO", "Envía a quien sea.\nSin instalar nada.", "Un enlace cifrado de hasta 100 GB que se abre en cualquier navegador."),
        "qr_beam": ("QR BEAM", "¿Sin red?\nDe pantalla a cámara.", "Sin Wi-Fi, punto de acceso ni Bluetooth. Ideal para texto, claves y archivos pequeños."),
        "rooms": ("SALAS", "Un código corto.\nTodos dentro.", "Comparte con un grupo. Cada uno toma lo que necesita."),
        "settings": ("PRIVADO DESDE EL DISEÑO", "Cifrado de\nextremo a extremo.", "Sin registro, sin correo, sin perfil. Nunca."),
    },
    "pt-BR": {
        "share": ("TRANSFERÊNCIA MULTIPLATAFORMA", "Envie qualquer coisa.\nPara qualquer aparelho.", "Na hora, pelo seu próprio Wi-Fi. Grátis e sem conta."),
        "link": ("LINK SEGURO", "Envie para qualquer um.\nSem precisar de app.", "Um link criptografado de até 100 GB, aberto em qualquer navegador."),
        "qr_beam": ("QR BEAM", "Sem rede?\nDa tela para a câmera.", "Sem Wi-Fi, hotspot ou Bluetooth. Ideal para textos, chaves e arquivos pequenos."),
        "rooms": ("SALAS", "Um código curto.\nTodo mundo dentro.", "Compartilhe com um grupo. Cada um pega o que precisa."),
        "settings": ("PRIVADO DESDE A ORIGEM", "Criptografia de\nponta a ponta.", "Sem cadastro, sem e-mail, sem perfil. Nunca."),
    },
    "ru": {
        "share": ("ПЕРЕДАЧА МЕЖДУ ПЛАТФОРМАМИ", "Отправляйте что угодно.\nНа любое устройство.", "Мгновенно, через ваш Wi-Fi. Бесплатно и без аккаунта."),
        "link": ("ЗАЩИЩЁННАЯ ССЫЛКА", "Отправьте кому угодно.\nБез приложения.", "Зашифрованная ссылка до 100 ГБ открывается в любом браузере."),
        "qr_beam": ("QR BEAM", "Нет сети?\nС экрана в камеру.", "Без Wi-Fi, точки доступа и Bluetooth. Для текста, ключей и небольших файлов."),
        "rooms": ("КОМНАТЫ", "Один короткий код.\nВсе внутри.", "Делитесь с группой. Каждый берёт то, что ему нужно."),
        "settings": ("ПРИВАТНОСТЬ ПО УМОЛЧАНИЮ", "Сквозное\nшифрование.", "Без регистрации, почты и профиля. Никогда."),
    },
    "ja": {
        "share": ("クロスプラットフォーム転送", "なんでも送れる。\nどのデバイスにも。", "自分のWi-Fiですぐに。無料、アカウント不要。"),
        "link": ("安全なリンク", "誰にでも送れる。\nアプリは不要。", "最大100GBの暗号化リンク。どのブラウザでも開けます。"),
        "qr_beam": ("QR BEAM", "ネットワークなし？\n画面からカメラへ。", "Wi-Fi・テザリング・Bluetoothは不要。テキストや鍵、小さなファイルに。"),
        "rooms": ("ルーム", "短いコードひとつで\nみんな参加。", "グループで共有。必要なものをそれぞれ受け取れます。"),
        "settings": ("プライバシー重視の設計", "エンドツーエンドで\n暗号化。", "登録もメールもプロフィールも不要。これからも。"),
    },
    "ko": {
        "share": ("크로스 플랫폼 전송", "무엇이든 보내세요.\n어떤 기기로든.", "내 Wi-Fi로 바로. 무료, 계정 없이."),
        "link": ("안전한 링크", "누구에게나 보내세요.\n앱은 필요 없어요.", "최대 100GB 암호화 링크, 어떤 브라우저에서도 열립니다."),
        "qr_beam": ("QR BEAM", "네트워크가 없나요?\n화면에서 카메라로.", "Wi-Fi, 핫스팟, 블루투스 없이. 텍스트, 키, 작은 파일에 딱."),
        "rooms": ("룸", "짧은 코드 하나로\n모두 입장.", "그룹과 공유하세요. 각자 필요한 것만 받아요."),
        "settings": ("처음부터 프라이빗", "종단간\n암호화.", "가입도, 이메일도, 프로필도 없어요. 앞으로도."),
    },
    "zh-Hans": {
        "share": ("跨平台传输", "什么都能发，\n发给任何设备。", "通过你自己的 Wi-Fi 即时传输。免费，无需账号。"),
        "link": ("安全链接", "发给任何人，\n无需安装应用。", "最大 100 GB 的加密链接，任何浏览器都能打开。"),
        "qr_beam": ("QR BEAM", "没有网络？\n屏幕对准摄像头。", "无需 Wi-Fi、热点或蓝牙。适合文本、密钥和小文件。"),
        "rooms": ("房间", "一个短码，\n大家都能进。", "与群组分享，每个人各取所需。"),
        "settings": ("隐私优先", "端到端\n加密。", "无需注册、邮箱或个人资料。永远如此。"),
    },
    "zh-Hant": {
        "share": ("跨平台傳輸", "什麼都能傳，\n傳給任何裝置。", "透過你自己的 Wi-Fi 即時傳輸。免費，不需帳號。"),
        "link": ("安全連結", "傳給任何人，\n不需安裝 App。", "最大 100 GB 的加密連結，任何瀏覽器都能開啟。"),
        "qr_beam": ("QR BEAM", "沒有網路？\n螢幕對準相機。", "不需 Wi-Fi、熱點或藍牙。適合文字、金鑰和小檔案。"),
        "rooms": ("房間", "一組短碼，\n大家都能加入。", "與群組分享，每個人各取所需。"),
        "settings": ("隱私優先", "端對端\n加密。", "不需註冊、電子郵件或個人檔案。永遠如此。"),
    },
    "ar": {
        "share": ("نقل بين جميع المنصات", "أرسل أي شيء.\nإلى أي جهاز.", "فورًا عبر شبكة Wi-Fi الخاصة بك. مجانًا وبلا حساب."),
        "link": ("رابط آمن", "أرسل لأي شخص.\nدون الحاجة إلى تطبيق.", "رابط مشفّر حتى 100 غيغابايت، يُفتح في أي متصفح."),
        "qr_beam": ("QR BEAM", "لا توجد شبكة؟\nمن الشاشة إلى الكاميرا.", "بلا Wi-Fi أو نقطة اتصال أو بلوتوث. مثالي للنصوص والمفاتيح والملفات الصغيرة."),
        "rooms": ("الغرف", "رمز قصير واحد.\nالجميع في الداخل.", "شارك مع مجموعة، وليأخذ كلٌّ ما يحتاجه."),
        "settings": ("الخصوصية أولًا", "تشفير تام\nبين الطرفين.", "بلا تسجيل ولا بريد إلكتروني ولا ملف شخصي. أبدًا."),
    },
    "hi": {
        "share": ("क्रॉस-प्लैटफ़ॉर्म ट्रांसफ़र", "कुछ भी भेजें।\nकिसी भी डिवाइस पर।", "अपने ही Wi-Fi से, तुरंत। मुफ़्त, बिना अकाउंट।"),
        "link": ("सुरक्षित लिंक", "किसी को भी भेजें।\nऐप की ज़रूरत नहीं।", "100 GB तक का एन्क्रिप्टेड लिंक, किसी भी ब्राउज़र में खुलता है।"),
        "qr_beam": ("QR BEAM", "नेटवर्क नहीं?\nस्क्रीन से कैमरा।", "Wi-Fi, हॉटस्पॉट या Bluetooth के बिना। टेक्स्ट, की और छोटी फ़ाइलों के लिए बढ़िया।"),
        "rooms": ("रूम", "एक छोटा कोड।\nसब अंदर।", "ग्रुप के साथ शेयर करें। हर कोई अपनी ज़रूरत की चीज़ ले।"),
        "settings": ("शुरू से ही प्राइवेट", "एंड-टू-एंड\nएन्क्रिप्टेड।", "न साइन-अप, न ईमेल, न प्रोफ़ाइल। कभी नहीं।"),
    },
}

CHIPS: dict[str, dict] = {
    "en": {
        "share": [("{self}", "Visible · Ready"), ("Sent to Galaxy S25", "1.2 GB · encrypted")],
        "link": [("bishare.app/transfer", "Expires in 24 h"), ("One-time download", "Opens in any browser")],
        "qr_beam": [("Show a file", "Stream of QR codes"), ("Scan a file", "Point your camera")],
        "rooms": [("Room JK57", "3 devices joined"), ("Galaxy got it", "Just now")],
        "settings": [("AES-256-GCM", "End-to-end encrypted"), ("No account", "Nothing to sign up for")],
        # the Mac has no camera scan: the phone reads the code the Mac shows
        "_mac": {"qr_beam": [("Show a file", "Stream of QR codes"), ("Your phone scans it", "With the BIShare camera")]},
    },
    "id": {
        "share": [("{self}", "Terlihat · Siap"), ("Terkirim ke Galaxy S25", "1,2 GB · terenkripsi")],
        "link": [("bishare.app/transfer", "Kedaluwarsa dalam 24 jam"), ("Unduh sekali", "Dibuka di browser apa pun")],
        "qr_beam": [("Tampilkan file", "Rangkaian kode QR"), ("Pindai file", "Arahkan kamera")],
        "rooms": [("Ruangan JK57", "3 perangkat bergabung"), ("Galaxy menerimanya", "Baru saja")],
        "settings": [("AES-256-GCM", "Terenkripsi end-to-end"), ("Tanpa akun", "Tidak perlu mendaftar")],
        "_mac": {"qr_beam": [("Tampilkan file", "Rangkaian kode QR"), ("Ponsel memindainya", "Dengan kamera BIShare")]},
    },
    "de": {
        "share": [("{self}", "Sichtbar · Bereit"), ("An Galaxy S25 gesendet", "1,2 GB · verschlüsselt")],
        "link": [("bishare.app/transfer", "Läuft nach 24 Std. ab"), ("Einmal-Download", "Öffnet in jedem Browser")],
        "qr_beam": [("Datei zeigen", "Folge von QR-Codes"), ("Datei scannen", "Kamera darauf richten")],
        "rooms": [("Raum JK57", "3 Geräte beigetreten"), ("Galaxy hat sie", "Gerade eben")],
        "settings": [("AES-256-GCM", "Ende-zu-Ende verschlüsselt"), ("Kein Konto", "Keine Registrierung")],
        "_mac": {"qr_beam": [("Datei zeigen", "Folge von QR-Codes"), ("Das Handy scannt", "Mit der BIShare-Kamera")]},
    },
    "fr": {
        "share": [("{self}", "Visible · Prêt"), ("Envoyé à Galaxy S25", "1,2\u00a0Go · chiffré")],
        "link": [("bishare.app/transfer", "Expire dans 24\u00a0h"), ("Téléchargement unique", "S'ouvre dans tout navigateur")],
        "qr_beam": [("Afficher un fichier", "Suite de codes QR"), ("Scanner un fichier", "Visez avec la caméra")],
        "rooms": [("Salon JK57", "3 appareils connectés"), ("Galaxy l'a reçu", "À l'instant")],
        "settings": [("AES-256-GCM", "Chiffré de bout en bout"), ("Aucun compte", "Rien à créer")],
        "_mac": {"qr_beam": [("Afficher un fichier", "Suite de codes QR"), ("Le téléphone le scanne", "Avec la caméra BIShare")]},
    },
    "es": {
        "share": [("{self}", "Visible · Listo"), ("Enviado a Galaxy S25", "1,2 GB · cifrado")],
        "link": [("bishare.app/transfer", "Caduca en 24 h"), ("Descarga única", "Se abre en cualquier navegador")],
        "qr_beam": [("Mostrar un archivo", "Serie de códigos QR"), ("Escanear un archivo", "Apunta la cámara")],
        "rooms": [("Sala JK57", "3 dispositivos dentro"), ("Galaxy lo recibió", "Ahora mismo")],
        "settings": [("AES-256-GCM", "Cifrado de extremo a extremo"), ("Sin cuenta", "Nada que registrar")],
        "_mac": {"qr_beam": [("Mostrar un archivo", "Serie de códigos QR"), ("Tu teléfono lo escanea", "Con la cámara de BIShare")]},
    },
    "pt-BR": {
        "share": [("{self}", "Visível · Pronto"), ("Enviado para Galaxy S25", "1,2 GB · criptografado")],
        "link": [("bishare.app/transfer", "Expira em 24 h"), ("Download único", "Abre em qualquer navegador")],
        "qr_beam": [("Mostrar um arquivo", "Sequência de códigos QR"), ("Escanear um arquivo", "Aponte a câmera")],
        "rooms": [("Sala JK57", "3 aparelhos conectados"), ("Galaxy recebeu", "Agora mesmo")],
        "settings": [("AES-256-GCM", "Criptografia de ponta a ponta"), ("Sem conta", "Nada para cadastrar")],
        "_mac": {"qr_beam": [("Mostrar um arquivo", "Sequência de códigos QR"), ("O celular escaneia", "Com a câmera do BIShare")]},
    },
    "ru": {
        "share": [("{self}", "Виден · Готов"), ("Отправлено на Galaxy S25", "1,2 ГБ · зашифровано")],
        "link": [("bishare.app/transfer", "Истекает через 24 ч"), ("Одно скачивание", "Открывается в любом браузере")],
        "qr_beam": [("Показать файл", "Поток QR-кодов"), ("Сканировать файл", "Наведите камеру")],
        "rooms": [("Комната JK57", "3 устройства в комнате"), ("Galaxy получил", "Только что")],
        "settings": [("AES-256-GCM", "Сквозное шифрование"), ("Без аккаунта", "Регистрация не нужна")],
        "_mac": {"qr_beam": [("Показать файл", "Поток QR-кодов"), ("Телефон сканирует", "Камерой в BIShare")]},
    },
    "ja": {
        "share": [("{self}", "表示中・準備完了"), ("Galaxy S25に送信済み", "1.2 GB・暗号化")],
        "link": [("bishare.app/transfer", "24時間で期限切れ"), ("1回限りのダウンロード", "どのブラウザでも開ける")],
        "qr_beam": [("ファイルを表示", "QRコードを連続表示"), ("ファイルをスキャン", "カメラを向けるだけ")],
        "rooms": [("ルーム JK57", "3台が参加中"), ("Galaxyが受信", "たった今")],
        "settings": [("AES-256-GCM", "エンドツーエンド暗号化"), ("アカウント不要", "登録は一切なし")],
        "_mac": {"qr_beam": [("ファイルを表示", "QRコードを連続表示"), ("スマホで読み取り", "BIShareのカメラで")]},
    },
    "ko": {
        "share": [("{self}", "표시됨 · 준비 완료"), ("Galaxy S25로 전송됨", "1.2GB · 암호화")],
        "link": [("bishare.app/transfer", "24시간 후 만료"), ("1회 다운로드", "어떤 브라우저에서도 열림")],
        "qr_beam": [("파일 보여주기", "연속 QR 코드"), ("파일 스캔", "카메라를 비추세요")],
        "rooms": [("룸 JK57", "3대 참여 중"), ("Galaxy가 받음", "방금")],
        "settings": [("AES-256-GCM", "종단간 암호화"), ("계정 없음", "가입할 것이 없어요")],
        "_mac": {"qr_beam": [("파일 보여주기", "연속 QR 코드"), ("휴대폰으로 스캔", "BIShare 카메라로")]},
    },
    "zh-Hans": {
        "share": [("{self}", "可见 · 就绪"), ("已发送到 Galaxy S25", "1.2 GB · 已加密")],
        "link": [("bishare.app/transfer", "24 小时后过期"), ("仅限下载一次", "任何浏览器都能打开")],
        "qr_beam": [("显示文件", "连续的二维码"), ("扫描文件", "对准摄像头即可")],
        "rooms": [("房间 JK57", "3 台设备已加入"), ("Galaxy 已收到", "刚刚")],
        "settings": [("AES-256-GCM", "端到端加密"), ("无需账号", "无需任何注册")],
        "_mac": {"qr_beam": [("显示文件", "连续的二维码"), ("用手机扫描", "使用 BIShare 相机")]},
    },
    "zh-Hant": {
        "share": [("{self}", "可見 · 就緒"), ("已傳送到 Galaxy S25", "1.2 GB · 已加密")],
        "link": [("bishare.app/transfer", "24 小時後失效"), ("僅限下載一次", "任何瀏覽器都能開啟")],
        "qr_beam": [("顯示檔案", "連續的 QR 碼"), ("掃描檔案", "對準相機即可")],
        "rooms": [("房間 JK57", "3 台裝置已加入"), ("Galaxy 已收到", "剛剛")],
        "settings": [("AES-256-GCM", "端對端加密"), ("不需帳號", "無須任何註冊")],
        "_mac": {"qr_beam": [("顯示檔案", "連續的 QR 碼"), ("用手機掃描", "使用 BIShare 相機")]},
    },
    "ar": {
        "share": [("{self}", "مرئي · جاهز"), ("أُرسل إلى Galaxy S25", "1.2 غيغابايت · مشفّر")],
        "link": [("bishare.app/transfer", "ينتهي بعد 24 ساعة"), ("تنزيل لمرة واحدة", "يُفتح في أي متصفح")],
        "qr_beam": [("اعرض ملفًا", "سلسلة رموز QR"), ("امسح ملفًا", "وجّه الكاميرا")],
        "rooms": [("الغرفة JK57", "انضمت 3 أجهزة"), ("استلمه Galaxy", "الآن")],
        "settings": [("AES-256-GCM", "تشفير تام بين الطرفين"), ("بلا حساب", "لا شيء للتسجيل")],
        "_mac": {"qr_beam": [("اعرض ملفًا", "سلسلة رموز QR"), ("يمسحه هاتفك", "بكاميرا BIShare")]},
    },
    "hi": {
        "share": [("{self}", "दिख रहा है · तैयार"), ("Galaxy S25 को भेजा गया", "1.2 GB · एन्क्रिप्टेड")],
        "link": [("bishare.app/transfer", "24 घंटे में समाप्त"), ("एक बार डाउनलोड", "किसी भी ब्राउज़र में खुलता है")],
        "qr_beam": [("फ़ाइल दिखाएँ", "QR कोड की लड़ी"), ("फ़ाइल स्कैन करें", "कैमरा सामने रखें")],
        "rooms": [("रूम JK57", "3 डिवाइस जुड़े"), ("Galaxy को मिल गया", "अभी-अभी")],
        "settings": [("AES-256-GCM", "एंड-टू-एंड एन्क्रिप्टेड"), ("कोई अकाउंट नहीं", "साइन-अप की ज़रूरत नहीं")],
        "_mac": {"qr_beam": [("फ़ाइल दिखाएँ", "QR कोड की लड़ी"), ("फ़ोन स्कैन करता है", "BIShare कैमरे से")]},
    },
}
