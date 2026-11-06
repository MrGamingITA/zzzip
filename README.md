<p align="center"><img src="assets/AppIcon-1024.png" width="160" alt="Zzzip icon"></p>

<h1 align="center">Zzzip</h1>
<p align="center"><b>Open archives, don't just unpack them.</b><br>
A free, open-source archive manager for macOS · <a href="#italiano">Italiano</a> · <a href="#english">English</a></p>

---

## English

When you double-click a `.zip`, `.rar` or `.7z`, Zzzip opens it in a window instead of dumping its contents on your desktop. You look inside, pick what you need, and extract it where you want.

### Features

- **Browse** with a sidebar folder tree, a sortable column list, a path bar and search across the whole archive.
- **Extract** with *Extract Here* or *Extract To…*, or drop items on *Desktop*, *Downloads*, *Documents* or your favorite folders in the sidebar.
  - Smart rule: a single item lands directly in the destination; several items go into a new folder named after the archive.
  - When a file already exists you choose *Replace*, *Skip* or *Keep Both*.
- **Drag out** files and folders straight to the Finder.
- **Open and Quick Look** files without extracting them first. If you edit an opened file, Zzzip offers to update it inside the archive.
- **Add and delete** files in zip, 7z, tar and wim archives. Changes are made on a safe copy, so the original is never left half-written.
- **Create** zip, 7z, tar, tar.gz, tar.bz2 and tar.xz archives.
  - Options: compression level, AES-256 password, encrypted file names, split volumes, and skipping Mac clutter (`.DS_Store`, `._*`).
- **Finder Quick Action:** right-click ▸ *Compress with Zzzip*.
- **Formats it opens:** zip, 7z, rar/rar5, tar, gz, bz2, xz, zst, lz4, cab, arj, lzh, cpio, wim, iso, dmg, xar/pkg, and split volumes.
- **Passwords,** including archives with encrypted headers.
- **Test** an archive's integrity and see its **Info**.
- **Language:** English and Italian, following your Mac's language.
- **Automatic updates** from GitHub Releases, signed and verified. You can turn them off in *Settings ▸ Updates*.
- **Privacy:** no analytics. The only network access is the update check, which you can switch off. Your files never leave your Mac.

### Install

#### Option A: download (easiest)

1. Download `Zzzip-x.y.z.dmg` from the [latest release](../../releases/latest).
2. Open it and drag **Zzzip** into **Applications**.
3. **First launch only:** Zzzip is free and isn't signed with a paid Apple developer certificate, so macOS asks you to confirm.
   1. Double-click Zzzip. macOS says it can't verify the developer. Click **Done** (or **OK**).
   2. Open **System Settings ▸ Privacy & Security**, scroll down and click **Open Anyway** next to "Zzzip was blocked…".
   3. Confirm with your password or Touch ID, then click **Open**.

   From then on Zzzip opens normally.

   *Prefer the Terminal?* This does the same in one line:
   `xattr -dr com.apple.quarantine /Applications/Zzzip.app`
4. In Zzzip, click **Make Zzzip the default app for archives**, or go to *Settings ▸ File Types*.

#### Option B: build from source

You need macOS 14 or later and [Xcode](https://apps.apple.com/app/xcode/id497799835), opened at least once. [Homebrew](https://brew.sh) is recommended.

```bash
git clone https://github.com/MrGamingITA/zzzip.git
cd zzzip
./scripts/install.sh
```

The script installs XcodeGen if needed, downloads the official 7-Zip engine, builds Zzzip and installs it in `/Applications`. An app you build yourself opens without any security prompt.

### Uninstall

Drag `/Applications/Zzzip.app` to the Trash. To also remove its settings, run:
`defaults delete io.github.mrgamingita.zzzip; rm -rf ~/Library/Caches/Zzzip`

---

## Italiano

Quando fai doppio clic su un `.zip`, `.rar` o `.7z`, Zzzip lo apre in una finestra invece di spargere il contenuto sulla Scrivania. Guardi dentro, scegli cosa ti serve e lo estrai dove vuoi.

### Funzioni

- **Sfogli** l'archivio con l'albero delle cartelle, l'elenco a colonne ordinabile, la barra del percorso e la ricerca in tutto l'archivio.
- **Estrai** con *Estrai qui* o *Estrai in…*, oppure trascinando gli elementi su *Scrivania*, *Download*, *Documenti* o sulle tue cartelle preferite nella barra laterale.
  - Regola intelligente: un solo elemento va direttamente nella destinazione; più elementi finiscono in una nuova cartella con il nome dell'archivio.
  - Se un file esiste già scegli tu: *Sostituisci*, *Salta* o *Mantieni entrambi*.
- **Trascini fuori** file e cartelle direttamente nel Finder.
- **Apri e vedi l'anteprima** dei file senza estrarli prima. Se modifichi un file aperto, Zzzip ti propone di aggiornarlo dentro l'archivio.
- **Aggiungi ed elimini** file negli archivi zip, 7z, tar e wim. Le modifiche avvengono su una copia di sicurezza, così l'originale non resta mai a metà.
- **Crei** archivi zip, 7z, tar, tar.gz, tar.bz2 e tar.xz.
  - Opzioni: livello di compressione, password AES-256, nomi dei file cifrati, divisione in volumi ed esclusione dei file nascosti del Mac (`.DS_Store`, `._*`).
- **Azione rapida del Finder:** tasto destro ▸ *Comprimi con Zzzip*.
- **Formati che apre:** zip, 7z, rar/rar5, tar, gz, bz2, xz, zst, lz4, cab, arj, lzh, cpio, wim, iso, dmg, xar/pkg e volumi divisi.
- **Password,** anche per gli archivi con intestazioni cifrate.
- **Verifica** l'integrità di un archivio e vedine le **Info**.
- **Lingua:** italiano e inglese, secondo la lingua del Mac.
- **Aggiornamenti automatici** dalle release di GitHub, firmati e verificati. Si possono spegnere in *Impostazioni ▸ Aggiornamenti*.
- **Privacy:** nessuna statistica. L'unico accesso alla rete è il controllo degli aggiornamenti, che puoi disattivare. I tuoi file non lasciano mai il Mac.

### Installazione

#### Opzione A: download (la più semplice)

1. Scarica `Zzzip-x.y.z.dmg` dall'[ultima release](../../releases/latest).
2. Aprilo e trascina **Zzzip** in **Applicazioni**.
3. **Solo al primo avvio:** Zzzip è gratuito e non è firmato con un certificato Apple a pagamento, quindi macOS ti chiede una conferma.
   1. Fai doppio clic su Zzzip. macOS dice che non può verificare lo sviluppatore. Clicca **Fine** (o **OK**).
   2. Apri **Impostazioni di Sistema ▸ Privacy e sicurezza**, scorri in basso e clicca **Apri comunque** accanto a "Zzzip è stato bloccato…".
   3. Conferma con la password o il Touch ID, poi clicca **Apri**.

   Da quel momento Zzzip si apre normalmente.

   *Preferisci il Terminale?* Questa riga fa la stessa cosa:
   `xattr -dr com.apple.quarantine /Applications/Zzzip.app`
4. In Zzzip clicca **Rendi Zzzip l'app predefinita per gli archivi**, oppure vai in *Impostazioni ▸ Tipi di file*.

#### Opzione B: compilalo tu

Ti servono macOS 14 o successivo e [Xcode](https://apps.apple.com/app/xcode/id497799835), aperto almeno una volta. [Homebrew](https://brew.sh) è consigliato.

```bash
git clone https://github.com/MrGamingITA/zzzip.git
cd zzzip
./scripts/install.sh
```

Lo script installa XcodeGen se serve, scarica il motore ufficiale 7-Zip, compila Zzzip e lo mette in `/Applicazioni`. Un'app compilata da te si apre senza avvisi di sicurezza.

### Disinstallazione

Trascina `/Applicazioni/Zzzip.app` nel Cestino. Per togliere anche le impostazioni, esegui:
`defaults delete io.github.mrgamingita.zzzip; rm -rf ~/Library/Caches/Zzzip`

---

## For developers

| Command | What it does |
|---|---|
| `scripts/fetch-7zz.sh` | Downloads official 7-Zip 26.05 (`7zz` + license) into `Vendor/7zip/` |
| `scripts/test.sh` | Runs the XCTest suite (unit + integration tests against the real 7zz) |
| `scripts/build-and-install.sh` | Release build → `/Applications/Zzzip.app` |
| `scripts/make-dmg.sh` | Release build → `build/dist/Zzzip-<version>.dmg` + SHA-256, for GitHub Releases |
| `scripts/release.sh 1.1.0 [notes.md]` | Bumps the version, runs the tests and builds the DMG. Then it signs the update with the Sparkle EdDSA key (`zzzip` in the Keychain), creates the GitHub release and updates `appcast.xml`. |
| `python3 scripts/make-icon.py assets/PandaCuscino.png` | Regenerates the app and document icons (needs Pillow) |

Layout:
- `Zzzip/Core` holds the archive logic, which is unit-tested: the 7zz runner, parser, extractor, editor and creator.
- `Zzzip/UI` holds the AppKit and SwiftUI interface.

### Updates

Installed copies read `appcast.xml` from the `main` branch. They only install DMGs signed with the private EdDSA key that matches `SUPublicEDKey` in `Info.plist`.

**Back up that key**, because without it you can't ship updates:
1. Export it with `build/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys --account zzzip -x zzzip-sparkle-key.txt`.
2. Store the file somewhere safe and never commit it.

## License

Zzzip is released under the [MIT License](LICENSE).
It bundles [7-Zip](https://www.7-zip.org) 26.05 by Igor Pavlov, licensed under the GNU LGPL with the unRAR restriction (`Vendor/7zip/License.txt`, also shown in *About Zzzip*).
