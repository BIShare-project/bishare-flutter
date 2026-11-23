#!/usr/bin/env python3
"""Microsoft Store listing for BIShare, all languages, as Partner Center CSV.

Partner Center cannot be reached through the submission API from this
account (creating the Entra tenant fails with 715-123280), so the listing goes
in through "Import and export Store listings": export the CSV from Partner
Center, run

    python3 store/msstore_listing.py <exported.csv> <out.csv>

and import <out.csv>. Only the fields below are written; every other cell of
the exported file is kept as it was. Screenshots, the store logo and the
trailer of the new languages point at the English assets already in Partner
Center until localized Windows screenshots exist.

Keyword choices come from Google Search Console queries per language
(2026-11) and the App Store keyword fields in listing.json. Store limits:
description 10,000 characters, features 200 each, up to 7 search terms of at
most 30 characters and 21 words in total.
"""

import csv
import sys

TITLE = "BIShare — File Transfer"  # the reserved product name

# Titles must be names reserved in Partner Center (Product identity), or the
# import fails. Chosen from Semrush volumes 2026-11-23: in every market the
# biggest safe query is moving PHOTOS from an iPhone to a PC (US "transfer
# photos from iphone to pc" 3,600; DE "fotos vom iphone auf pc" 1,900; ES
# "pasar fotos de iphone a pc" 1,600; ID "...foto dari iphone ke laptop"
# 1,600 - laptop, not PC; JP "iphone 写真 パソコン 取り込み" 1,000).
# "AirDrop" stays out of titles: it is Apple's trademark.
TITLE_EN = "BIShare: iPhone to PC Photo & File Transfer"
TITLES = {
    "en": TITLE_EN,
    "en-us": TITLE_EN,
    "id": "BIShare: Pindah Foto & File iPhone ke Laptop",
    "es": "BIShare: Pasar Fotos y Archivos de iPhone a PC",
    "de": "BIShare: Fotos & Dateien vom iPhone auf PC",
    "fr": "BIShare : Transférer Photos iPhone vers PC",
    "pt": "BIShare: Transferir Fotos do iPhone para o PC",
    "ja": "BIShare: iPhone写真・ファイルをパソコンへ転送",
}

# CSV column -> listing. "en" and "en-us" carry the same text; "zh" is the
# Traditional Chinese listing.
LISTINGS = {}

LISTINGS["en"] = {
    "short": (
        "Send files from iPhone to PC, Android to PC and PC to any phone over "
        "your own Wi-Fi — no cable, no iTunes, no cloud upload. BIShare is a "
        "free, open-source AirDrop alternative for Windows: full-quality "
        "photos and videos, end-to-end encrypted, no ads and no account "
        "needed to send."
    ),
    "description": """Send files from iPhone to PC, Android to PC, and from Windows to any phone, tablet or computer — over your own Wi-Fi, with no cable, no iTunes and no cloud upload. BIShare is a free, open-source AirDrop alternative for Windows that works with iPhone, iPad, Android, Mac and Linux.

IPHONE TO PC WITHOUT ITUNES OR A CABLE
A USB cable only shows Windows your iPhone's photos. BIShare moves anything: videos at full size, photos in their original format, PDFs, documents, ZIP files and whole folders. Install BIShare on the iPhone and on the PC, join the same Wi-Fi, choose the files and tap your PC. It works the other way too: send from the PC to an iPhone, iPad or Android phone.

FAST, LOCAL AND PRIVATE
On the same Wi-Fi, devices find each other automatically and files move at router speed, straight from one device to the other. Nothing is recompressed: photos and videos arrive at full resolution with their original "Date modified". Every local transfer is end-to-end encrypted (X25519 key exchange, AES-256-GCM).

SEND TO SOMEONE FAR AWAY
Not on the same network? Create an encrypted link of up to 100 GB. The file is encrypted on your PC before upload, the link expires after 24 hours, and the recipient opens it in any browser — no app and no account needed.

WHAT YOU GET
• iPhone to PC and PC to iPhone, Android to PC and PC to Android, Windows to Mac and Linux
• Large file transfer with no size limit on your own network
• Encrypted share links up to 100 GB, free
• Rooms: share one short code and several devices join at once
• Clipboard sync between your own devices on the same Wi-Fi (off until you turn it on)
• Drag and drop files onto a device; keep receiving in the background from the system tray
• Drive: 5 GB of free encrypted cloud storage across your devices, with optional larger plans

FREE AND OPEN SOURCE
Sending files is free, with no ads and no sign-up. BIShare is open source under the Apache License 2.0 (GitHub: BIShare-project).

BIShare is not affiliated with Apple. AirDrop is a trademark of Apple Inc., used here only to describe what BIShare does.""",
    "features": [
        "Send files from iPhone to PC and PC to iPhone — no cable, no iTunes, no iCloud",
        "Android to PC, PC to Android, and Windows to Mac or Linux over Wi-Fi",
        "Transfers at local Wi-Fi speed; nothing is uploaded to the cloud",
        "Photos and videos keep full resolution, original format and Date modified",
        "End-to-end encrypted with X25519 and AES-256-GCM",
        "Encrypted share links up to 100 GB, free; recipients only need a browser",
        "Rooms: one short code, several devices sharing at once",
        "Drag and drop, and keep receiving in the background from the system tray",
    ],
    "terms": [
        "iphone to pc",
        "airdrop for windows",
        "transfer photos iphone to pc",
        "android to pc",
        "send large files",
        "wifi file transfer",
    ],
    "notes": "Version 2.9.3\n\n• The window can now be resized and maximized.\n\nFree and open source under the Apache License 2.0.",
    "trailer": "BIShare: send files from your PC to any device",
}
LISTINGS["en-us"] = LISTINGS["en"]

LISTINGS["id"] = {
    "short": (
        "Kirim file dari iPhone ke PC, Android ke PC, dan dari PC ke HP apa "
        "pun lewat Wi-Fi Anda sendiri — tanpa kabel, tanpa iTunes, tanpa "
        "unggah ke cloud. BIShare adalah alternatif AirDrop untuk Windows yang "
        "gratis dan open source: foto dan video kualitas penuh, terenkripsi "
        "end-to-end, tanpa iklan dan tanpa akun untuk mengirim."
    ),
    "description": """Kirim file dari iPhone ke PC, dari Android ke PC, dan dari Windows ke HP, tablet, atau komputer apa pun — lewat Wi-Fi Anda sendiri, tanpa kabel, tanpa iTunes, dan tanpa unggah ke cloud. BIShare adalah alternatif AirDrop untuk Windows yang gratis dan open source, dan bekerja dengan iPhone, iPad, Android, Mac, dan Linux.

IPHONE KE PC TANPA ITUNES ATAU KABEL
Lewat kabel USB, Windows hanya bisa melihat foto di iPhone. BIShare memindahkan apa saja: video ukuran penuh, foto dalam format aslinya, PDF, dokumen, file ZIP, dan seluruh folder. Pasang BIShare di iPhone dan di PC, sambungkan keduanya ke Wi-Fi yang sama, pilih file, lalu ketuk PC Anda. Arah sebaliknya juga bisa: kirim dari PC ke iPhone, iPad, atau HP Android.

CEPAT, LOKAL, DAN PRIVAT
Di Wi-Fi yang sama, perangkat saling menemukan secara otomatis dan file berpindah secepat router Anda, langsung dari satu perangkat ke perangkat lain. Tidak ada kompresi ulang: foto dan video tiba dengan resolusi penuh dan "Tanggal diubah" aslinya. Setiap transfer lokal terenkripsi end-to-end (pertukaran kunci X25519, AES-256-GCM).

KIRIM KE ORANG YANG JAUH
Tidak di jaringan yang sama? Buat tautan terenkripsi hingga 100 GB. File dienkripsi di PC Anda sebelum diunggah, tautan kedaluwarsa setelah 24 jam, dan penerima cukup membukanya di browser — tanpa aplikasi dan tanpa akun.

FITUR
• iPhone ke PC dan PC ke iPhone, Android ke PC dan PC ke Android, Windows ke Mac dan Linux
• Kirim file besar tanpa batas ukuran di jaringan Anda sendiri
• Tautan berbagi terenkripsi hingga 100 GB, gratis
• Rooms: bagikan satu kode pendek dan beberapa perangkat bergabung sekaligus
• Sinkronisasi clipboard antar perangkat Anda sendiri di Wi-Fi yang sama (mati sampai Anda menyalakannya)
• Seret dan lepas file ke perangkat; tetap menerima di latar belakang dari system tray
• Drive: penyimpanan cloud terenkripsi gratis 5 GB untuk semua perangkat Anda, dengan paket lebih besar bila perlu

GRATIS DAN OPEN SOURCE
Mengirim file gratis, tanpa iklan dan tanpa daftar. BIShare open source dengan Apache License 2.0 (GitHub: BIShare-project).

BIShare tidak berafiliasi dengan Apple. AirDrop adalah merek dagang Apple Inc., disebut di sini hanya untuk menjelaskan fungsi BIShare.""",
    "features": [
        "Kirim file dari iPhone ke PC dan PC ke iPhone — tanpa kabel, tanpa iTunes, tanpa iCloud",
        "Android ke PC, PC ke Android, serta Windows ke Mac atau Linux lewat Wi-Fi",
        "Transfer secepat Wi-Fi lokal; tidak ada yang diunggah ke cloud",
        "Foto dan video tetap resolusi penuh, format asli, dan Tanggal diubah aslinya",
        "Terenkripsi end-to-end dengan X25519 dan AES-256-GCM",
        "Tautan berbagi terenkripsi hingga 100 GB, gratis; penerima cukup pakai browser",
        "Rooms: satu kode pendek, beberapa perangkat berbagi sekaligus",
        "Seret dan lepas, dan tetap menerima di latar belakang dari system tray",
    ],
    "terms": [
        "pindah foto iphone ke laptop",
        "airdrop windows",
        "transfer file android ke pc",
        "kirim file besar",
        "transfer file wifi",
        "berbagi file",
    ],
    "notes": "Versi 2.9.3\n\n• Jendela kini bisa diubah ukurannya dan dimaksimalkan.\n\nGratis dan open source dengan Apache License 2.0.",
    "trailer": "BIShare: kirim file dari PC ke perangkat apa pun",
}

LISTINGS["es"] = {
    "short": (
        "Pasa archivos del iPhone al PC, de Android al PC y del PC a cualquier "
        "teléfono por tu propia Wi-Fi, sin cable, sin iTunes y sin subir nada "
        "a la nube. BIShare es una alternativa a AirDrop para Windows gratuita "
        "y de código abierto: fotos y vídeos en calidad original, cifrado de "
        "extremo a extremo, sin anuncios y sin cuenta para enviar."
    ),
    "description": """Pasa archivos del iPhone al PC, de Android al PC y de Windows a cualquier teléfono, tableta u ordenador, por tu propia Wi-Fi, sin cable, sin iTunes y sin subir nada a la nube. BIShare es una alternativa a AirDrop para Windows, gratuita y de código abierto, que funciona con iPhone, iPad, Android, Mac y Linux.

DEL IPHONE AL PC SIN ITUNES NI CABLE
Con un cable USB, Windows solo ve las fotos del iPhone. BIShare mueve cualquier cosa: vídeos a tamaño completo, fotos en su formato original, PDF, documentos, archivos ZIP y carpetas enteras. Instala BIShare en el iPhone y en el PC, conéctalos a la misma Wi-Fi, elige los archivos y toca tu PC. También funciona al revés: envía desde el PC a un iPhone, un iPad o un teléfono Android.

RÁPIDO, LOCAL Y PRIVADO
En la misma Wi-Fi, los dispositivos se encuentran solos y los archivos viajan a la velocidad del router, directamente de un dispositivo a otro. Nada se recomprime: fotos y vídeos llegan con su resolución completa y su "Fecha de modificación" original. Cada transferencia local está cifrada de extremo a extremo (intercambio de claves X25519, AES-256-GCM).

ENVÍA A QUIEN ESTÁ LEJOS
¿No están en la misma red? Crea un enlace cifrado de hasta 100 GB. El archivo se cifra en tu PC antes de subirse, el enlace caduca a las 24 horas y quien lo recibe lo abre en cualquier navegador, sin app y sin cuenta.

QUÉ INCLUYE
• iPhone a PC y PC a iPhone, Android a PC y PC a Android, Windows a Mac y Linux
• Envía archivos grandes sin límite de tamaño en tu propia red
• Enlaces cifrados de hasta 100 GB, gratis
• Salas (Rooms): comparte un código corto y varios dispositivos se unen a la vez
• Portapapeles sincronizado entre tus dispositivos en la misma Wi-Fi (desactivado hasta que lo actives)
• Arrastra y suelta archivos sobre un dispositivo; sigue recibiendo en segundo plano desde la bandeja del sistema
• Drive: 5 GB gratis de almacenamiento cifrado en la nube para todos tus dispositivos, con planes más grandes opcionales

GRATIS Y DE CÓDIGO ABIERTO
Enviar archivos es gratis, sin anuncios y sin registro. BIShare es de código abierto con la licencia Apache 2.0 (GitHub: BIShare-project).

BIShare no está afiliado a Apple. AirDrop es una marca registrada de Apple Inc., mencionada aquí solo para describir lo que hace BIShare.""",
    "features": [
        "Pasa archivos del iPhone al PC y del PC al iPhone, sin cable, sin iTunes y sin iCloud",
        "De Android al PC, del PC a Android y de Windows a Mac o Linux por Wi-Fi",
        "Transferencias a la velocidad de tu Wi-Fi; nada se sube a la nube",
        "Fotos y vídeos con resolución completa, formato original y fecha de modificación",
        "Cifrado de extremo a extremo con X25519 y AES-256-GCM",
        "Enlaces cifrados de hasta 100 GB, gratis; basta con un navegador para recibir",
        "Salas: un código corto y varios dispositivos compartiendo a la vez",
        "Arrastrar y soltar, y recepción en segundo plano desde la bandeja del sistema",
    ],
    "terms": [
        "airdrop para windows",
        "pasar fotos iphone a pc",
        "enviar archivos grandes",
        "transferir archivos",
        "android a pc",
        "airdrop para pc",
        "compartir archivos",
    ],
    "notes": "Versión 2.9.3\n\n• Ahora la ventana se puede redimensionar y maximizar.\n\nGratis y de código abierto con la licencia Apache 2.0.",
    "trailer": "BIShare: envía archivos del PC a cualquier dispositivo",
}

LISTINGS["fr"] = {
    "short": (
        "Transférez des fichiers de l'iPhone vers le PC, d'Android vers le PC "
        "et du PC vers n'importe quel téléphone via votre propre Wi-Fi, sans "
        "câble, sans iTunes et sans passer par le cloud. BIShare est une "
        "alternative à AirDrop pour Windows, gratuite et open source : photos "
        "et vidéos en qualité d'origine, chiffrement de bout en bout, sans "
        "publicité et sans compte pour envoyer."
    ),
    "description": """Transférez des fichiers de l'iPhone vers le PC, d'Android vers le PC et de Windows vers n'importe quel téléphone, tablette ou ordinateur, via votre propre Wi-Fi, sans câble, sans iTunes et sans passer par le cloud. BIShare est une alternative à AirDrop pour Windows, gratuite et open source, qui fonctionne avec iPhone, iPad, Android, Mac et Linux.

DE L'IPHONE AU PC SANS ITUNES NI CÂBLE
Avec un câble USB, Windows ne voit que les photos de l'iPhone. BIShare transfère tout : vidéos en taille réelle, photos dans leur format d'origine, PDF, documents, fichiers ZIP et dossiers entiers. Installez BIShare sur l'iPhone et sur le PC, connectez-les au même Wi-Fi, choisissez les fichiers et touchez votre PC. Ça marche aussi dans l'autre sens : envoyez du PC vers un iPhone, un iPad ou un téléphone Android.

RAPIDE, LOCAL ET PRIVÉ
Sur le même Wi-Fi, les appareils se trouvent automatiquement et les fichiers passent à la vitesse du routeur, directement d'un appareil à l'autre. Rien n'est recompressé : photos et vidéos arrivent en pleine résolution, avec leur « Date de modification » d'origine. Chaque transfert local est chiffré de bout en bout (échange de clés X25519, AES-256-GCM).

ENVOYEZ À QUELQU'UN DE LOIN
Pas sur le même réseau ? Créez un lien chiffré jusqu'à 100 Go. Le fichier est chiffré sur votre PC avant l'envoi, le lien expire au bout de 24 heures et le destinataire l'ouvre dans n'importe quel navigateur, sans application ni compte.

CE QUE VOUS OBTENEZ
• iPhone vers PC et PC vers iPhone, Android vers PC et PC vers Android, Windows vers Mac et Linux
• Envoi de gros fichiers sans limite de taille sur votre propre réseau
• Liens de partage chiffrés jusqu'à 100 Go, gratuits
• Salons (Rooms) : partagez un code court et plusieurs appareils se connectent en même temps
• Presse-papiers synchronisé entre vos appareils sur le même Wi-Fi (désactivé tant que vous ne l'activez pas)
• Glisser-déposer des fichiers sur un appareil ; réception en arrière-plan depuis la zone de notification
• Drive : 5 Go de stockage cloud chiffré gratuit pour tous vos appareils, avec des forfaits plus grands en option

GRATUIT ET OPEN SOURCE
L'envoi de fichiers est gratuit, sans publicité ni inscription. BIShare est open source sous licence Apache 2.0 (GitHub: BIShare-project).

BIShare n'est pas affilié à Apple. AirDrop est une marque d'Apple Inc., citée ici uniquement pour décrire ce que fait BIShare.""",
    "features": [
        "Transférez des fichiers de l'iPhone vers le PC et inversement, sans câble, iTunes ni iCloud",
        "Android vers PC, PC vers Android, et Windows vers Mac ou Linux par Wi-Fi",
        "Transferts à la vitesse de votre Wi-Fi ; rien n'est envoyé dans le cloud",
        "Photos et vidéos en pleine résolution, format d'origine et date de modification conservés",
        "Chiffrement de bout en bout avec X25519 et AES-256-GCM",
        "Liens chiffrés jusqu'à 100 Go, gratuits ; un navigateur suffit pour recevoir",
        "Salons : un code court, plusieurs appareils qui partagent en même temps",
        "Glisser-déposer, et réception en arrière-plan depuis la zone de notification",
    ],
    "terms": [
        "airdrop pour pc",
        "airdrop pour windows",
        "transférer photos iphone pc",
        "envoyer gros fichiers",
        "android vers pc",
        "partage de fichiers",
        "transfert wifi",
    ],
    "notes": "Version 2.9.3\n\n• La fenêtre peut désormais être redimensionnée et agrandie.\n\nGratuit et open source sous licence Apache 2.0.",
    "trailer": "BIShare : envoyez des fichiers du PC vers n'importe quel appareil",
}

LISTINGS["de"] = {
    "short": (
        "Übertragen Sie Dateien vom iPhone auf den PC, von Android auf den PC "
        "und vom PC auf jedes Handy – über Ihr eigenes WLAN, ohne Kabel, ohne "
        "iTunes und ohne Cloud-Upload. BIShare ist eine kostenlose "
        "Open-Source-Alternative zu AirDrop für Windows: Fotos und Videos in "
        "Originalqualität, Ende-zu-Ende-verschlüsselt, ohne Werbung und ohne "
        "Konto zum Senden."
    ),
    "description": """Übertragen Sie Dateien vom iPhone auf den PC, von Android auf den PC und von Windows auf jedes Handy, Tablet oder jeden Computer – über Ihr eigenes WLAN, ohne Kabel, ohne iTunes und ohne Cloud-Upload. BIShare ist eine kostenlose Open-Source-Alternative zu AirDrop für Windows und funktioniert mit iPhone, iPad, Android, Mac und Linux.

VOM IPHONE AUF DEN PC OHNE ITUNES ODER KABEL
Per USB-Kabel sieht Windows nur die Fotos des iPhones. BIShare überträgt alles: Videos in voller Größe, Fotos im Originalformat, PDFs, Dokumente, ZIP-Dateien und ganze Ordner. Installieren Sie BIShare auf dem iPhone und dem PC, verbinden Sie beide mit demselben WLAN, wählen Sie die Dateien aus und tippen Sie auf Ihren PC. Auch umgekehrt: Senden Sie vom PC an ein iPhone, iPad oder Android-Handy.

SCHNELL, LOKAL UND PRIVAT
Im selben WLAN finden sich die Geräte automatisch, und Dateien werden mit Router-Geschwindigkeit direkt von Gerät zu Gerät übertragen. Nichts wird neu komprimiert: Fotos und Videos kommen in voller Auflösung und mit ihrem ursprünglichen Änderungsdatum an. Jede lokale Übertragung ist Ende-zu-Ende-verschlüsselt (X25519-Schlüsselaustausch, AES-256-GCM).

GROSSE DATEIEN AN JEMANDEN IN DER FERNE SENDEN
Nicht im selben Netzwerk? Erstellen Sie einen verschlüsselten Link für bis zu 100 GB. Die Datei wird vor dem Hochladen auf Ihrem PC verschlüsselt, der Link läuft nach 24 Stunden ab, und der Empfänger öffnet ihn in jedem Browser – ohne App und ohne Konto.

FUNKTIONEN
• iPhone auf PC und PC auf iPhone, Android auf PC und PC auf Android, Windows auf Mac und Linux
• Große Dateien senden, ohne Größenlimit im eigenen Netzwerk
• Verschlüsselte Freigabelinks bis 100 GB, kostenlos
• Räume (Rooms): einen kurzen Code teilen, und mehrere Geräte treten gleichzeitig bei
• Zwischenablage zwischen Ihren eigenen Geräten im selben WLAN synchronisieren (aus, bis Sie es einschalten)
• Dateien per Drag-and-drop auf ein Gerät ziehen; Empfang im Hintergrund über den Infobereich
• Drive: 5 GB kostenloser verschlüsselter Cloud-Speicher für alle Ihre Geräte, größere Tarife optional

KOSTENLOS UND OPEN SOURCE
Dateien senden ist kostenlos, ohne Werbung und ohne Anmeldung. BIShare ist Open Source unter der Apache License 2.0 (GitHub: BIShare-project).

BIShare steht in keiner Verbindung zu Apple. AirDrop ist eine Marke der Apple Inc. und wird hier nur genannt, um zu beschreiben, was BIShare tut.""",
    "features": [
        "Dateien vom iPhone auf den PC und zurück – ohne Kabel, ohne iTunes, ohne iCloud",
        "Android auf PC, PC auf Android und Windows auf Mac oder Linux per WLAN",
        "Übertragung mit WLAN-Geschwindigkeit; nichts wird in die Cloud hochgeladen",
        "Fotos und Videos behalten volle Auflösung, Originalformat und Änderungsdatum",
        "Ende-zu-Ende-verschlüsselt mit X25519 und AES-256-GCM",
        "Verschlüsselte Links bis 100 GB, kostenlos; zum Empfangen genügt ein Browser",
        "Räume: ein kurzer Code, mehrere Geräte teilen gleichzeitig",
        "Drag-and-drop und Empfang im Hintergrund über den Infobereich",
    ],
    "terms": [
        "airdrop für windows",
        "fotos vom iphone auf pc",
        "große dateien senden",
        "große dateien versenden",
        "android auf pc",
        "dateien übertragen",
    ],
    "notes": "Version 2.9.3\n\n• Das Fenster lässt sich jetzt in der Größe ändern und maximieren.\n\nKostenlos und Open Source unter der Apache License 2.0.",
    "trailer": "BIShare: Dateien vom PC an jedes Gerät senden",
}

LISTINGS["pt"] = {
    "short": (
        "Passe arquivos do iPhone para o PC, do Android para o PC e do PC para "
        "qualquer celular pelo seu próprio Wi-Fi, sem cabo, sem iTunes e sem "
        "enviar nada para a nuvem. BIShare é uma alternativa ao AirDrop para "
        "Windows, gratuita e de código aberto: fotos e vídeos em qualidade "
        "original, criptografia de ponta a ponta, sem anúncios e sem conta "
        "para enviar."
    ),
    "description": """Passe arquivos do iPhone para o PC, do Android para o PC e do Windows para qualquer celular, tablet ou computador pelo seu próprio Wi-Fi, sem cabo, sem iTunes e sem enviar nada para a nuvem. BIShare é uma alternativa ao AirDrop para Windows, gratuita e de código aberto, que funciona com iPhone, iPad, Android, Mac e Linux.

DO IPHONE PARA O PC SEM ITUNES NEM CABO
Pelo cabo USB, o Windows só enxerga as fotos do iPhone. O BIShare transfere tudo: vídeos em tamanho original, fotos no formato original, PDFs, documentos, arquivos ZIP e pastas inteiras. Instale o BIShare no iPhone e no PC, conecte os dois ao mesmo Wi-Fi, escolha os arquivos e toque no seu PC. Também funciona ao contrário: envie do PC para um iPhone, iPad ou celular Android.

RÁPIDO, LOCAL E PRIVADO
No mesmo Wi-Fi, os aparelhos se encontram sozinhos e os arquivos passam na velocidade do roteador, direto de um aparelho para o outro. Nada é recomprimido: fotos e vídeos chegam com resolução total e a "Data de modificação" original. Toda transferência local tem criptografia de ponta a ponta (troca de chaves X25519, AES-256-GCM).

ENVIE PARA QUEM ESTÁ LONGE
Não estão na mesma rede? Crie um link criptografado de até 100 GB. O arquivo é criptografado no seu PC antes do envio, o link expira em 24 horas e quem recebe abre em qualquer navegador, sem app e sem conta.

O QUE VOCÊ GANHA
• iPhone para PC e PC para iPhone, Android para PC e PC para Android, Windows para Mac e Linux
• Envio de arquivos grandes sem limite de tamanho na sua própria rede
• Links criptografados de até 100 GB, grátis
• Salas (Rooms): compartilhe um código curto e vários aparelhos entram ao mesmo tempo
• Área de transferência sincronizada entre seus aparelhos no mesmo Wi-Fi (desligada até você ativar)
• Arraste e solte arquivos em um aparelho; continue recebendo em segundo plano pela bandeja do sistema
• Drive: 5 GB grátis de armazenamento em nuvem criptografado para todos os seus aparelhos, com planos maiores opcionais

GRÁTIS E DE CÓDIGO ABERTO
Enviar arquivos é grátis, sem anúncios e sem cadastro. O BIShare é de código aberto sob a licença Apache 2.0 (GitHub: BIShare-project).

O BIShare não tem afiliação com a Apple. AirDrop é uma marca registrada da Apple Inc., citada aqui apenas para descrever o que o BIShare faz.""",
    "features": [
        "Passe arquivos do iPhone para o PC e do PC para o iPhone, sem cabo, iTunes ou iCloud",
        "Android para PC, PC para Android e Windows para Mac ou Linux pelo Wi-Fi",
        "Transferências na velocidade do seu Wi-Fi; nada vai para a nuvem",
        "Fotos e vídeos com resolução total, formato original e data de modificação",
        "Criptografia de ponta a ponta com X25519 e AES-256-GCM",
        "Links criptografados de até 100 GB, grátis; para receber basta um navegador",
        "Salas: um código curto, vários aparelhos compartilhando ao mesmo tempo",
        "Arrastar e soltar, e recebimento em segundo plano pela bandeja do sistema",
    ],
    "terms": [
        "airdrop para pc",
        "airdrop para windows",
        "transferir fotos iphone pc",
        "enviar arquivos grandes",
        "android para pc",
        "transferir arquivos",
        "compartilhar arquivos",
    ],
    "notes": "Versão 2.9.3\n\n• Agora a janela pode ser redimensionada e maximizada.\n\nGrátis e de código aberto sob a licença Apache 2.0.",
    "trailer": "BIShare: envie arquivos do PC para qualquer aparelho",
}

LISTINGS["ru"] = {
    "short": (
        "Передавайте файлы с iPhone на ПК, с Android на ПК и с ПК на любой "
        "телефон через свой Wi-Fi — без кабеля, без iTunes и без загрузки в "
        "облако. BIShare — бесплатная альтернатива AirDrop для Windows с "
        "открытым исходным кодом: фото и видео в исходном качестве, сквозное "
        "шифрование, без рекламы и без аккаунта для отправки."
    ),
    "description": """Передавайте файлы с iPhone на компьютер, с Android на компьютер и с Windows на любой телефон, планшет или компьютер — через свой Wi-Fi, без кабеля, без iTunes и без загрузки в облако. BIShare — бесплатная альтернатива AirDrop для Windows с открытым исходным кодом. Работает с iPhone, iPad, Android, Mac и Linux.

С IPHONE НА ПК БЕЗ ITUNES И КАБЕЛЯ
По USB-кабелю Windows видит только фотографии iPhone. BIShare передаёт всё: видео в полном размере, фото в исходном формате, PDF, документы, ZIP-архивы и целые папки. Установите BIShare на iPhone и на ПК, подключите их к одной сети Wi-Fi, выберите файлы и нажмите на свой ПК. В обратную сторону тоже работает: отправляйте с ПК на iPhone, iPad или Android-смартфон.

БЫСТРО, ЛОКАЛЬНО И ПРИВАТНО
В одной сети Wi-Fi устройства находят друг друга автоматически, а файлы идут напрямую с устройства на устройство со скоростью роутера. Ничего не пережимается: фото и видео приходят в полном разрешении и с исходной датой изменения. Каждая локальная передача защищена сквозным шифрованием (обмен ключами X25519, AES-256-GCM).

ОТПРАВКА НА РАССТОЯНИЕ
Не в одной сети? Создайте зашифрованную ссылку до 100 ГБ. Файл шифруется на вашем ПК до загрузки, ссылка действует 24 часа, а получатель открывает её в любом браузере — без приложения и без аккаунта.

ВОЗМОЖНОСТИ
• iPhone на ПК и ПК на iPhone, Android на ПК и ПК на Android, Windows на Mac и Linux
• Передача больших файлов без ограничения размера в вашей сети
• Зашифрованные ссылки до 100 ГБ бесплатно
• Комнаты (Rooms): поделитесь коротким кодом, и несколько устройств подключатся сразу
• Синхронизация буфера обмена между вашими устройствами в одной сети Wi-Fi (выключена, пока вы её не включите)
• Перетаскивайте файлы на устройство; приём в фоне из области уведомлений
• Drive: 5 ГБ бесплатного зашифрованного облачного хранилища для всех ваших устройств и более крупные тарифы по желанию

БЕСПЛАТНО И С ОТКРЫТЫМ КОДОМ
Отправка файлов бесплатна, без рекламы и регистрации. Исходный код BIShare открыт под лицензией Apache 2.0 (GitHub: BIShare-project).

BIShare не связан с Apple. AirDrop — товарный знак Apple Inc., упомянутый здесь только для описания возможностей BIShare.""",
    "features": [
        "Файлы с iPhone на ПК и с ПК на iPhone — без кабеля, iTunes и iCloud",
        "С Android на ПК, с ПК на Android, с Windows на Mac или Linux по Wi-Fi",
        "Скорость вашего Wi-Fi; ничего не загружается в облако",
        "Фото и видео сохраняют полное разрешение, исходный формат и дату изменения",
        "Сквозное шифрование X25519 и AES-256-GCM",
        "Зашифрованные ссылки до 100 ГБ бесплатно; получателю нужен только браузер",
        "Комнаты: один короткий код, несколько устройств обмениваются одновременно",
        "Перетаскивание файлов и приём в фоне из области уведомлений",
    ],
    "terms": [
        "airdrop для windows",
        "с iphone на компьютер",
        "передача файлов",
        "большие файлы",
        "с android на пк",
        "обмен файлами",
        "airdrop для пк",
    ],
    "notes": "Версия 2.9.3\n\n• Окно теперь можно изменять по размеру и разворачивать.\n\nБесплатно и с открытым исходным кодом под лицензией Apache 2.0.",
    "trailer": "BIShare: отправляйте файлы с ПК на любое устройство",
}

LISTINGS["ja"] = {
    "short": (
        "iPhoneからパソコン、Androidからパソコン、パソコンから各種スマホへ、"
        "自分のWi-Fiでファイルを転送。ケーブルもiTunesもクラウドへのアップロードも"
        "不要です。BIShareはWindows向けの無料・オープンソースのAirDrop代替アプリ。"
        "写真や動画は元の画質のまま、エンドツーエンド暗号化、広告なし、"
        "送信にアカウントは不要です。"
    ),
    "description": """iPhoneからパソコン、Androidからパソコン、そしてWindowsからスマホ・タブレット・パソコンへ。自分のWi-Fiでファイルを転送でき、ケーブルもiTunesもクラウドへのアップロードも必要ありません。BIShareはWindows向けの無料・オープンソースのAirDrop代替アプリで、iPhone、iPad、Android、Mac、Linuxに対応しています。

iTunesもケーブルも不要でiPhoneからPCへ
USBケーブルでは、WindowsからはiPhoneの写真しか見えません。BIShareなら何でも送れます。フルサイズの動画、元の形式のままの写真、PDF、書類、ZIPファイル、フォルダごと。iPhoneとPCにBIShareを入れて同じWi-Fiにつなぎ、ファイルを選んでPCをタップするだけ。逆方向も同じく、PCからiPhone、iPad、Androidスマホへ送れます。

速く、ローカルで、プライベート
同じWi-Fiなら端末どうしが自動で見つかり、ファイルはルーターの速度で端末から端末へ直接届きます。再圧縮は一切なし。写真や動画はフル解像度のまま、元の「更新日時」も保たれます。ローカル転送はすべてエンドツーエンドで暗号化されます（X25519鍵交換、AES-256-GCM）。

離れた相手にも送れる
同じネットワークにいない相手には、最大100GBの暗号化リンクを作成。ファイルはアップロード前にPC上で暗号化され、リンクは24時間で期限切れになります。受け取る側はブラウザで開くだけで、アプリもアカウントも不要です。

主な機能
• iPhone⇄PC、Android⇄PC、WindowsからMac・Linuxへ
• 自分のネットワーク内ならサイズ無制限で大容量ファイルを送信
• 最大100GBの暗号化共有リンクが無料
• ルーム：短いコードを共有するだけで複数の端末が同時に参加
• 同じWi-Fi上の自分の端末どうしでクリップボードを同期（オンにするまではオフ）
• ファイルを端末にドラッグ＆ドロップ。システムトレイからバックグラウンドで受信
• Drive：すべての端末で使える5GBの無料暗号化クラウドストレージ。大容量プランも選べます

無料でオープンソース
ファイルの送信は無料で、広告も登録もありません。BIShareはApache License 2.0のオープンソースです（GitHub：BIShare-project）。

BIShareはAppleとは関係ありません。AirDropはApple Inc.の商標であり、ここではBIShareの機能を説明するためにのみ使用しています。""",
    "features": [
        "iPhoneからPC、PCからiPhoneへ。ケーブル・iTunes・iCloud不要",
        "AndroidからPC、PCからAndroid、WindowsからMac・LinuxへWi-Fiで転送",
        "Wi-Fiの速度でそのまま転送。クラウドには何もアップロードしません",
        "写真や動画はフル解像度・元の形式・更新日時をそのまま保持",
        "X25519とAES-256-GCMによるエンドツーエンド暗号化",
        "最大100GBの暗号化リンクが無料。受け取りはブラウザだけでOK",
        "ルーム：短いコードひとつで複数の端末が同時に共有",
        "ドラッグ＆ドロップ対応、システムトレイからバックグラウンド受信",
    ],
    "terms": [
        "windows エアドロップ",
        "iphone 写真 パソコン 取り込み",
        "android パソコン 転送",
        "大容量ファイル 送信",
        "ファイル共有アプリ",
        "エアドロ windows",
        "iphone android 動画 送る",
    ],
    "notes": "バージョン 2.9.3\n\n• ウィンドウのサイズ変更と最大化ができるようになりました。\n\nApache License 2.0の無料オープンソースです。",
    "trailer": "BIShare：PCからあらゆる端末へファイルを送信",
}

LISTINGS["ko"] = {
    "short": (
        "내 Wi-Fi로 아이폰에서 PC로, 안드로이드에서 PC로, PC에서 어떤 "
        "휴대폰으로든 파일을 보내세요. 케이블도, iTunes도, 클라우드 업로드도 "
        "필요 없습니다. BIShare는 무료 오픈 소스 Windows용 AirDrop 대안입니다. "
        "사진과 동영상은 원본 화질 그대로, 종단 간 암호화, 광고 없음, 보낼 때 "
        "계정도 필요 없습니다."
    ),
    "description": """내 Wi-Fi로 아이폰에서 PC로, 안드로이드에서 PC로, Windows에서 어떤 휴대폰·태블릿·컴퓨터로든 파일을 보내세요. 케이블도, iTunes도, 클라우드 업로드도 필요 없습니다. BIShare는 무료 오픈 소스 Windows용 AirDrop 대안이며 iPhone, iPad, Android, Mac, Linux에서 작동합니다.

iTunes나 케이블 없이 아이폰에서 PC로
USB 케이블로 연결하면 Windows에서는 아이폰 사진만 보입니다. BIShare는 무엇이든 옮깁니다. 원본 크기 동영상, 원본 형식 사진, PDF, 문서, ZIP 파일, 폴더 전체까지. 아이폰과 PC에 BIShare를 설치하고 같은 Wi-Fi에 연결한 뒤 파일을 골라 PC를 탭하세요. 반대 방향도 됩니다. PC에서 아이폰, 아이패드, 안드로이드 폰으로 보낼 수 있습니다.

빠르고, 로컬이며, 비공개
같은 Wi-Fi에서는 기기가 서로를 자동으로 찾고, 파일은 공유기 속도로 기기에서 기기로 바로 전송됩니다. 재압축은 없습니다. 사진과 동영상은 원본 해상도와 원래의 '수정한 날짜' 그대로 도착합니다. 모든 로컬 전송은 종단 간 암호화됩니다(X25519 키 교환, AES-256-GCM).

멀리 있는 사람에게도 전송
같은 네트워크가 아닌가요? 최대 100GB의 암호화 링크를 만드세요. 파일은 업로드 전에 PC에서 암호화되고, 링크는 24시간 후 만료되며, 받는 사람은 어떤 브라우저에서든 앱이나 계정 없이 열 수 있습니다.

주요 기능
• 아이폰↔PC, 안드로이드↔PC, Windows에서 Mac·Linux로
• 내 네트워크에서는 크기 제한 없이 대용량 파일 전송
• 최대 100GB 암호화 공유 링크 무료
• 룸: 짧은 코드 하나로 여러 기기가 동시에 참여
• 같은 Wi-Fi의 내 기기끼리 클립보드 동기화(직접 켜기 전까지 꺼져 있음)
• 파일을 기기로 드래그 앤 드롭, 시스템 트레이에서 백그라운드 수신
• Drive: 모든 기기에서 쓰는 5GB 무료 암호화 클라우드 저장공간, 더 큰 요금제는 선택

무료 오픈 소스
파일 전송은 무료이며 광고와 가입이 없습니다. BIShare는 Apache License 2.0 오픈 소스입니다 (GitHub: BIShare-project).

BIShare는 Apple과 관련이 없습니다. AirDrop은 Apple Inc.의 상표이며 여기서는 BIShare의 기능을 설명하기 위해서만 언급합니다.""",
    "features": [
        "아이폰에서 PC로, PC에서 아이폰으로 — 케이블, iTunes, iCloud 없이",
        "안드로이드↔PC, Windows에서 Mac·Linux로 Wi-Fi 전송",
        "Wi-Fi 속도로 전송, 클라우드에 아무것도 올리지 않음",
        "사진·동영상의 원본 해상도, 형식, 수정한 날짜 유지",
        "X25519와 AES-256-GCM 종단 간 암호화",
        "최대 100GB 암호화 링크 무료, 받는 사람은 브라우저만 있으면 됨",
        "룸: 짧은 코드 하나로 여러 기기가 동시에 공유",
        "드래그 앤 드롭, 시스템 트레이에서 백그라운드 수신",
    ],
    "terms": [
        "에어드롭 윈도우",
        "아이폰 pc 파일 전송",
        "안드로이드 pc 파일 전송",
        "대용량 파일 전송",
        "와이파이 파일 전송",
        "파일 공유",
        "airdrop windows",
    ],
    "notes": "버전 2.9.3\n\n• 이제 창 크기를 조절하고 최대화할 수 있습니다.\n\nApache License 2.0 무료 오픈 소스입니다.",
    "trailer": "BIShare: PC에서 모든 기기로 파일 보내기",
}

LISTINGS["zh-hans"] = {
    "short": (
        "通过自己的 Wi-Fi，把文件从 iPhone 传到电脑、从安卓传到电脑，或从电脑"
        "传到任意手机。无需数据线、无需 iTunes，也不上传到云端。BIShare 是免费"
        "开源的 Windows 版 AirDrop 替代工具：照片和视频保持原画质，端到端加密，"
        "无广告，发送无需注册账号。"
    ),
    "description": """通过自己的 Wi-Fi，把文件从 iPhone 传到电脑、从安卓传到电脑，或从 Windows 传到任意手机、平板或电脑。无需数据线、无需 iTunes，也不上传到云端。BIShare 是免费开源的 Windows 版 AirDrop（隔空投送）替代工具，支持 iPhone、iPad、Android、Mac 和 Linux。

iPhone 传电脑，无需 iTunes 和数据线
用 USB 数据线连接时，Windows 只能看到 iPhone 里的照片。BIShare 什么都能传：原尺寸视频、原格式照片、PDF、文档、ZIP 文件，甚至整个文件夹。在 iPhone 和电脑上安装 BIShare，连接同一 Wi-Fi，选好文件，点一下你的电脑即可。反过来也一样：从电脑发到 iPhone、iPad 或安卓手机。

快速、本地、私密
在同一 Wi-Fi 下，设备会自动发现彼此，文件以路由器速度在设备之间直接传输。不做任何二次压缩：照片和视频以原始分辨率到达，并保留原来的"修改日期"。每次本地传输都经过端到端加密（X25519 密钥交换，AES-256-GCM）。

远程发送
不在同一网络？创建最大 100 GB 的加密链接。文件在上传前于你的电脑上加密，链接 24 小时后失效，对方用任意浏览器即可打开，无需安装应用，也无需账号。

功能一览
• iPhone 与电脑互传，安卓与电脑互传，Windows 传 Mac 和 Linux
• 在自己的网络中传大文件，不限大小
• 免费的加密分享链接，最大 100 GB
• 房间（Rooms）：分享一个短码，多台设备同时加入
• 同一 Wi-Fi 下自己设备之间的剪贴板同步（默认关闭，需手动开启）
• 把文件拖放到设备上即可发送；最小化到系统托盘后台接收
• Drive：所有设备通用的 5 GB 免费加密云存储，可选更大容量套餐

免费开源
发送文件免费，无广告、无需注册。BIShare 基于 Apache License 2.0 开源（GitHub：BIShare-project）。

BIShare 与 Apple 无关联。AirDrop 是 Apple Inc. 的商标，此处仅用于说明 BIShare 的功能。""",
    "features": [
        "iPhone 与电脑互传文件，无需数据线、iTunes 或 iCloud",
        "安卓与电脑互传，Windows 也能通过 Wi-Fi 传到 Mac 或 Linux",
        "以 Wi-Fi 速度传输，不上传任何内容到云端",
        "照片和视频保留原始分辨率、格式和修改日期",
        "X25519 与 AES-256-GCM 端到端加密",
        "免费加密链接最大 100 GB，对方只需浏览器即可接收",
        "房间：一个短码，多台设备同时分享",
        "支持拖放，系统托盘后台接收",
    ],
    "terms": [
        "iphone传文件到电脑",
        "安卓传文件到电脑",
        "隔空投送 windows",
        "airdrop windows",
        "大文件传输",
        "局域网传文件",
        "电脑手机互传",
    ],
    "notes": "版本 2.9.3\n\n• 窗口现在可以调整大小和最大化。\n\n基于 Apache License 2.0 免费开源。",
    "trailer": "BIShare：从电脑向任意设备发送文件",
}

LISTINGS["zh"] = {
    "short": (
        "透過自己的 Wi-Fi，把檔案從 iPhone 傳到電腦、從 Android 傳到電腦，或從"
        "電腦傳到任何手機。不需要傳輸線、不需要 iTunes，也不會上傳到雲端。"
        "BIShare 是免費開源的 Windows 版 AirDrop 替代工具：照片和影片維持原始"
        "畫質，端對端加密，沒有廣告，傳送也不需要帳號。"
    ),
    "description": """透過自己的 Wi-Fi，把檔案從 iPhone 傳到電腦、從 Android 傳到電腦，或從 Windows 傳到任何手機、平板或電腦。不需要傳輸線、不需要 iTunes，也不會上傳到雲端。BIShare 是免費開源的 Windows 版 AirDrop 替代工具，支援 iPhone、iPad、Android、Mac 和 Linux。

iPhone 傳電腦，不用 iTunes 也不用傳輸線
用 USB 傳輸線連接時，Windows 只看得到 iPhone 裡的照片。BIShare 什麼都能傳：原尺寸影片、原始格式照片、PDF、文件、ZIP 檔，甚至整個資料夾。在 iPhone 和電腦上安裝 BIShare，連上同一個 Wi-Fi，選好檔案，點一下你的電腦就完成。反方向也一樣：從電腦傳到 iPhone、iPad 或 Android 手機。

快速、本機、私密
在同一個 Wi-Fi 下，裝置會自動找到彼此，檔案以路由器速度在裝置之間直接傳送。完全不會重新壓縮：照片和影片以原始解析度送達，並保留原本的「修改日期」。每次本機傳輸都採用端對端加密（X25519 金鑰交換、AES-256-GCM）。

遠端傳送
不在同一個網路？建立最大 100 GB 的加密連結。檔案會在上傳前於你的電腦上加密，連結 24 小時後失效，對方用任何瀏覽器就能開啟，不必安裝 App，也不需要帳號。

功能一覽
• iPhone 與電腦互傳、Android 與電腦互傳、Windows 傳到 Mac 和 Linux
• 在自己的網路中傳送大檔案，不限大小
• 免費加密分享連結，最大 100 GB
• 房間（Rooms）：分享一組短代碼，多台裝置同時加入
• 同一個 Wi-Fi 下自己的裝置之間同步剪貼簿（預設關閉，需自行開啟）
• 把檔案拖放到裝置上即可傳送；縮到系統匣在背景接收
• Drive：所有裝置共用的 5 GB 免費加密雲端空間，也可選擇更大容量方案

免費開源
傳送檔案免費，沒有廣告，也不用註冊。BIShare 以 Apache License 2.0 開源（GitHub：BIShare-project）。

BIShare 與 Apple 無關。AirDrop 是 Apple Inc. 的商標，此處僅用於說明 BIShare 的功能。""",
    "features": [
        "iPhone 與電腦互傳檔案，不需要傳輸線、iTunes 或 iCloud",
        "Android 與電腦互傳，Windows 也能透過 Wi-Fi 傳到 Mac 或 Linux",
        "以 Wi-Fi 速度傳輸，不會上傳任何內容到雲端",
        "照片和影片保留原始解析度、格式和修改日期",
        "X25519 與 AES-256-GCM 端對端加密",
        "免費加密連結最大 100 GB，對方只需瀏覽器即可接收",
        "房間：一組短代碼，多台裝置同時分享",
        "支援拖放，系統匣背景接收",
    ],
    "terms": [
        "iphone傳檔案到電腦",
        "android傳檔案到電腦",
        "airdrop windows",
        "大檔案傳輸",
        "區網傳檔",
        "手機電腦互傳",
        "檔案分享",
    ],
    "notes": "版本 2.9.3\n\n• 視窗現在可以調整大小及最大化。\n\n以 Apache License 2.0 免費開源。",
    "trailer": "BIShare：從電腦傳送檔案到任何裝置",
}

LISTINGS["hi"] = {
    "short": (
        "अपने Wi-Fi से iPhone से PC, Android से PC और PC से किसी भी फ़ोन पर "
        "फ़ाइलें भेजें — बिना केबल, बिना iTunes और बिना क्लाउड अपलोड के। BIShare "
        "Windows के लिए मुफ़्त और ओपन सोर्स AirDrop विकल्प है: फ़ोटो और वीडियो "
        "ओरिजिनल क्वालिटी में, एंड-टू-एंड एन्क्रिप्टेड, कोई विज्ञापन नहीं और "
        "भेजने के लिए कोई अकाउंट नहीं।"
    ),
    "description": """अपने Wi-Fi से iPhone से PC, Android से PC और Windows से किसी भी फ़ोन, टैबलेट या कंप्यूटर पर फ़ाइलें भेजें — बिना केबल, बिना iTunes और बिना क्लाउड अपलोड के। BIShare Windows के लिए मुफ़्त और ओपन सोर्स AirDrop विकल्प है, जो iPhone, iPad, Android, Mac और Linux के साथ काम करता है।

iTunes या केबल के बिना iPhone से PC
USB केबल से Windows को iPhone की सिर्फ़ फ़ोटो दिखती हैं। BIShare सब कुछ भेजता है: पूरे साइज़ के वीडियो, ओरिजिनल फ़ॉर्मैट में फ़ोटो, PDF, दस्तावेज़, ZIP फ़ाइलें और पूरे फ़ोल्डर। iPhone और PC पर BIShare इंस्टॉल करें, दोनों को एक ही Wi-Fi से जोड़ें, फ़ाइलें चुनें और अपने PC पर टैप करें। उल्टी दिशा में भी काम करता है: PC से iPhone, iPad या Android फ़ोन पर भेजें।

तेज़, लोकल और प्राइवेट
एक ही Wi-Fi पर डिवाइस अपने-आप एक-दूसरे को ढूँढ लेते हैं और फ़ाइलें राउटर की स्पीड से सीधे एक डिवाइस से दूसरे पर जाती हैं। कुछ भी दोबारा कंप्रेस नहीं होता: फ़ोटो और वीडियो पूरे रेज़ोल्यूशन और ओरिजिनल "बदलाव की तारीख" के साथ पहुँचते हैं। हर लोकल ट्रांसफ़र एंड-टू-एंड एन्क्रिप्टेड है (X25519 की एक्सचेंज, AES-256-GCM)।

दूर बैठे व्यक्ति को भेजें
एक ही नेटवर्क पर नहीं हैं? 100 GB तक का एन्क्रिप्टेड लिंक बनाएँ। फ़ाइल अपलोड से पहले आपके PC पर एन्क्रिप्ट होती है, लिंक 24 घंटे बाद ख़त्म हो जाता है, और पाने वाला उसे किसी भी ब्राउज़र में खोल सकता है — न ऐप चाहिए, न अकाउंट।

क्या मिलता है
• iPhone से PC और PC से iPhone, Android से PC और PC से Android, Windows से Mac और Linux
• अपने नेटवर्क पर बिना साइज़ लिमिट के बड़ी फ़ाइलें भेजें
• 100 GB तक के एन्क्रिप्टेड शेयर लिंक, मुफ़्त
• रूम्स: एक छोटा कोड शेयर करें और कई डिवाइस एक साथ जुड़ जाएँ
• एक ही Wi-Fi पर अपने डिवाइस के बीच क्लिपबोर्ड सिंक (जब तक आप चालू न करें, बंद रहता है)
• फ़ाइलें ड्रैग-एंड-ड्रॉप से डिवाइस पर भेजें; सिस्टम ट्रे से बैकग्राउंड में रिसीव करें
• Drive: आपके सभी डिवाइस के लिए 5 GB मुफ़्त एन्क्रिप्टेड क्लाउड स्टोरेज, और चाहें तो बड़े प्लान

मुफ़्त और ओपन सोर्स
फ़ाइलें भेजना मुफ़्त है, बिना विज्ञापन और बिना साइन-अप। BIShare, Apache License 2.0 के तहत ओपन सोर्स है (GitHub: BIShare-project)।

BIShare का Apple से कोई संबंध नहीं है। AirDrop, Apple Inc. का ट्रेडमार्क है, जिसका ज़िक्र यहाँ सिर्फ़ यह बताने के लिए किया गया है कि BIShare क्या करता है।""",
    "features": [
        "iPhone से PC और PC से iPhone पर फ़ाइलें भेजें — बिना केबल, iTunes या iCloud",
        "Android से PC, PC से Android और Windows से Mac या Linux पर Wi-Fi से",
        "Wi-Fi की स्पीड से ट्रांसफ़र; क्लाउड पर कुछ भी अपलोड नहीं होता",
        "फ़ोटो और वीडियो का पूरा रेज़ोल्यूशन, ओरिजिनल फ़ॉर्मैट और तारीख बनी रहती है",
        "X25519 और AES-256-GCM से एंड-टू-एंड एन्क्रिप्शन",
        "100 GB तक के एन्क्रिप्टेड लिंक मुफ़्त; पाने वाले को सिर्फ़ ब्राउज़र चाहिए",
        "रूम्स: एक छोटा कोड, कई डिवाइस एक साथ शेयर करें",
        "ड्रैग-एंड-ड्रॉप, और सिस्टम ट्रे से बैकग्राउंड में रिसीव",
    ],
    "terms": [
        "airdrop for windows",
        "iphone to pc",
        "iphone se pc file transfer",
        "android to pc",
        "फ़ाइल ट्रांसफर",
        "file transfer app",
    ],
    "notes": "वर्ज़न 2.9.3\n\n• अब विंडो का साइज़ बदला और मैक्सिमाइज़ किया जा सकता है।\n\nApache License 2.0 के तहत मुफ़्त और ओपन सोर्स।",
    "trailer": "BIShare: PC से किसी भी डिवाइस पर फ़ाइलें भेजें",
}

LISTINGS["ar"] = {
    "short": (
        "انقل الملفات من الآيفون إلى الكمبيوتر، ومن أندرويد إلى الكمبيوتر، ومن "
        "الكمبيوتر إلى أي هاتف عبر شبكة Wi-Fi الخاصة بك، بلا كابل ولا iTunes ولا "
        "رفع إلى السحابة. BIShare بديل مجاني ومفتوح المصدر لـ AirDrop على "
        "ويندوز: صور وفيديوهات بجودتها الأصلية، وتشفير من طرف إلى طرف، بلا "
        "إعلانات وبلا حساب للإرسال."
    ),
    "description": """انقل الملفات من الآيفون إلى الكمبيوتر، ومن أندرويد إلى الكمبيوتر، ومن ويندوز إلى أي هاتف أو جهاز لوحي أو كمبيوتر عبر شبكة Wi-Fi الخاصة بك، بلا كابل ولا iTunes ولا رفع إلى السحابة. BIShare بديل مجاني ومفتوح المصدر لـ AirDrop على ويندوز، ويعمل مع iPhone وiPad وAndroid وMac وLinux.

من الآيفون إلى الكمبيوتر بلا iTunes ولا كابل
عبر كابل USB لا يرى ويندوز من الآيفون إلا الصور. أما BIShare فينقل كل شيء: الفيديوهات بحجمها الكامل، والصور بصيغتها الأصلية، وملفات PDF والمستندات وملفات ZIP ومجلدات كاملة. ثبّت BIShare على الآيفون والكمبيوتر، واتصل بشبكة Wi-Fi نفسها، واختر الملفات ثم اضغط على جهازك. ويعمل في الاتجاه المعاكس أيضًا: أرسل من الكمبيوتر إلى آيفون أو آيباد أو هاتف أندرويد.

سريع ومحلي وخاص
على شبكة Wi-Fi نفسها تتعرّف الأجهزة على بعضها تلقائيًا، وتنتقل الملفات بسرعة الراوتر مباشرة من جهاز إلى آخر. لا يُعاد ضغط أي شيء: تصل الصور والفيديوهات بدقتها الكاملة مع "تاريخ التعديل" الأصلي. كل نقل محلي مشفّر من طرف إلى طرف (تبادل مفاتيح X25519، وAES-256-GCM).

أرسل إلى من هو بعيد
لستما على الشبكة نفسها؟ أنشئ رابطًا مشفّرًا حتى 100 جيجابايت. يُشفَّر الملف على جهازك قبل رفعه، وتنتهي صلاحية الرابط بعد 24 ساعة، ويفتحه المستلم في أي متصفح دون تطبيق ودون حساب.

المزايا
• من الآيفون إلى الكمبيوتر والعكس، ومن أندرويد إلى الكمبيوتر والعكس، ومن ويندوز إلى Mac وLinux
• إرسال الملفات الكبيرة دون حد للحجم على شبكتك الخاصة
• روابط مشاركة مشفّرة حتى 100 جيجابايت مجانًا
• الغرف (Rooms): شارك رمزًا قصيرًا لتنضم عدة أجهزة في الوقت نفسه
• مزامنة الحافظة بين أجهزتك على شبكة Wi-Fi نفسها (متوقفة حتى تفعّلها)
• اسحب الملفات وأفلتها على أي جهاز، واستقبل في الخلفية من شريط النظام
• Drive: مساحة تخزين سحابية مشفّرة مجانية بسعة 5 جيجابايت لكل أجهزتك، مع خطط أكبر اختيارية

مجاني ومفتوح المصدر
إرسال الملفات مجاني، بلا إعلانات وبلا تسجيل. BIShare مفتوح المصدر بموجب ترخيص Apache 2.0 (GitHub: BIShare-project).

BIShare غير تابع لشركة Apple. ‏AirDrop علامة تجارية لشركة Apple Inc.، ويُذكر هنا فقط لوصف ما يقوم به BIShare.""",
    "features": [
        "انقل الملفات من الآيفون إلى الكمبيوتر والعكس بلا كابل ولا iTunes ولا iCloud",
        "من أندرويد إلى الكمبيوتر والعكس، ومن ويندوز إلى Mac أو Linux عبر Wi-Fi",
        "نقل بسرعة شبكة Wi-Fi، ولا يُرفع أي شيء إلى السحابة",
        "تحتفظ الصور والفيديوهات بدقتها الكاملة وصيغتها الأصلية وتاريخ تعديلها",
        "تشفير من طرف إلى طرف باستخدام X25519 وAES-256-GCM",
        "روابط مشفّرة حتى 100 جيجابايت مجانًا، ويكفي المستلم متصفح",
        "الغرف: رمز قصير واحد لمشاركة عدة أجهزة في الوقت نفسه",
        "السحب والإفلات، والاستقبال في الخلفية من شريط النظام",
    ],
    "terms": [
        "airdrop للويندوز",
        "نقل ملفات الايفون للكمبيوتر",
        "اندرويد إلى الكمبيوتر",
        "إرسال ملفات كبيرة",
        "مشاركة الملفات",
        "نقل الملفات عبر wifi",
        "airdrop للكمبيوتر",
    ],
    "notes": "الإصدار 2.9.3\n\n• أصبح بالإمكان الآن تغيير حجم النافذة وتكبيرها.\n\nمجاني ومفتوح المصدر بموجب ترخيص Apache 2.0.",
    "trailer": "BIShare: أرسل الملفات من الكمبيوتر إلى أي جهاز",
}

# Assets every listing reuses from the English one until it has its own.
# Partner Center refuses an asset URL that belongs to another language's
# listing, so only the English listing keeps its uploaded logo and trailer;
# the others get the logo as a file next to the CSV and no trailer.
SHARED_ASSETS = [f"DesktopScreenshot{i}" for i in range(1, 6)]
ROOT = "BIShare-msstore-import"  # the folder chosen in Partner Center
SHARED_TEXT = ["DevStudio", "CopyrightTrademarkInformation"]


def check():
    """Fail loudly on anything Partner Center would refuse."""
    for lang, d in LISTINGS.items():
        assert len(d["description"]) <= 10000, lang
        assert len(d["short"]) <= 1000, lang
        assert len(d["notes"]) <= 1500, lang
        assert 1 <= len(d["features"]) <= 20, lang
        for f in d["features"]:
            assert len(f) <= 200, (lang, f)
        assert len(d["terms"]) <= 7, lang
        for t in d["terms"]:
            assert len(t) <= 30, (lang, t)
        words = sum(len(t.split()) for t in d["terms"])
        assert words <= 21, (lang, words)
        assert "MIT" not in d["description"], lang
        assert "http" not in d["description"], lang  # no URLs allowed there


SHOT_FILES = ["01-send.png", "02-inbox.png", "03-secure-link.png", "04-drive.png", "05-settings.png"]
# CSV column -> store/screenshots/windows/<dir>
SHOT_DIR = {
    "en": "en", "en-us": "en", "ar": "ar", "zh": "zh-Hant", "zh-hans": "zh-Hans",
    "fr": "fr", "de": "de", "hi": "hi", "id": "id", "ja": "ja", "ko": "ko",
    "pt": "pt-BR", "ru": "ru", "es": "es",
}


def build(src, dst, shots=False, titles=False):
    check()
    with open(src, encoding="utf-8-sig", newline="") as fh:
        rows = list(csv.reader(fh))
    head = rows[0]
    col = {name: i for i, name in enumerate(head)}
    by_field = {r[0]: r for r in rows[1:]}
    missing = [lang for lang in LISTINGS if lang not in col]
    if missing:
        sys.exit(f"export has no column for {missing}: add the languages first")

    def put(field, lang, value):
        row = by_field[field]
        while len(row) < len(head):
            row.append("")
        row[col[lang]] = value

    for lang, d in LISTINGS.items():
        put("Title", lang, TITLES.get(lang, TITLE_EN) if titles else TITLE)
        put("ShortDescription", lang, d["short"])
        put("Description", lang, d["description"])
        put("ReleaseNotes", lang, d["notes"])
        if lang == "en":
            put("TrailerTitle1", lang, d["trailer"])
        for i in range(20):
            name = f"Feature{i + 1}"
            if name in by_field:
                put(name, lang, d["features"][i] if i < len(d["features"]) else "")
        for i in range(7):
            name = f"SearchTerm{i + 1}"
            if name in by_field:
                put(name, lang, d["terms"][i] if i < len(d["terms"]) else "")
        for field in SHARED_ASSETS + SHARED_TEXT:
            if field in by_field and lang != "en":
                put(field, lang, by_field[field][col["en"]])
        if shots:
            # Partner Center wants the imported folder's own name first
            for i, name in enumerate(SHOT_FILES):
                put(f"DesktopScreenshot{i + 1}", lang, f"{ROOT}/screenshots/{SHOT_DIR[lang]}/{name}")

    with open(dst, "w", encoding="utf-8-sig", newline="") as fh:
        csv.writer(fh, lineterminator="\r\n").writerows(rows)


if __name__ == "__main__":
    if len(sys.argv) == 1:
        check()
        print("listing text passes the store limits")
    else:
        # --shots: point every listing at its own screenshots, copied next
        # to the CSV as screenshots/<lang>/ (store/screenshots/windows/<lang>)
        # --titles: the new titles; only once every name in TITLES is reserved
        build(sys.argv[1], sys.argv[2], shots="--shots" in sys.argv[3:],
              titles="--titles" in sys.argv[3:])
