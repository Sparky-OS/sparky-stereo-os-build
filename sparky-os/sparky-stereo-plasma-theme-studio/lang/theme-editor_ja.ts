<?xml version="1.0" encoding="utf-8"?>
<!DOCTYPE TS>
<TS version="2.1" language="ja" sourcelanguage="en">
    <context>
        <name>Cli</name>
        <message>
            <source>Open an icon theme</source>
            <translation>アイコンテーマを開く</translation>
        </message>
        <message>
            <source>Open an SVG source inside the theme</source>
            <translation>テーマ内の SVG ソースを開く</translation>
        </message>
        <message>
            <source>Open a saved project</source>
            <translation>保存したプロジェクトを開く</translation>
        </message>
        <message>
            <source>Read group depths from JSON</source>
            <translation>JSON からグループの深度を読み込む</translation>
        </message>
        <message>
            <source>Save a new project copy</source>
            <translation>新しいプロジェクトのコピーを保存</translation>
        </message>
        <message>
            <source>Disable the stereo preview</source>
            <translation>ステレオプレビューを無効にする</translation>
        </message>
        <message>
            <source>Return after the requested save</source>
            <translation>指定の保存後に終了する</translation>
        </message>
        <message>
            <source>Cannot open the group choices</source>
            <translation>グループの設定を開けません</translation>
        </message>
        <message>
            <source>Invalid group choices</source>
            <translation>グループの設定が無効です</translation>
        </message>
    </context>
    <context>
        <name>Drawing</name>
        <message>
            <source>SVGZ decompression failed or timed out</source>
            <translation>SVGZ の展開に失敗したか、時間がかかりすぎました</translation>
        </message>
        <message>
            <source>Invalid or excessive SVGZ input</source>
            <translation>SVGZ 入力が無効か、大きすぎます</translation>
        </message>
        <message>
            <source>Cannot parse SVG</source>
            <translation>SVG を解析できません</translation>
        </message>
        <message>
            <source>SVG renderer rejected the drawing</source>
            <translation>SVG レンダラーが描画を読み込めませんでした</translation>
        </message>
        <message>
            <source>The SVG has no usable view box</source>
            <translation>SVG に使用可能な表示領域がありません</translation>
        </message>
        <message>
            <source>Duplicate SVG group id: </source>
            <translation>SVG グループ ID が重複しています: </translation>
        </message>
        <message>
            <source>This SVG has no named groups to author</source>
            <translation>この SVG には編集対象の名前付きグループがありません</translation>
        </message>
        <message>
            <source>Invalid desktop depth limits</source>
            <translation>デスクトップの深度制限が無効です</translation>
        </message>
        <message>
            <source>Invalid group or place</source>
            <translation>グループまたは位置が無効です</translation>
        </message>
        <message>
            <source>Scripted SVG is not supported</source>
            <translation>スクリプトを含む SVG は未対応です</translation>
        </message>
        <message>
            <source>Use inline SVG paint attributes; CSS stylesheets are not supported</source>
            <translation>SVG の描画属性を要素に直接指定してください。CSS スタイルシートは未対応です</translation>
        </message>
        <message>
            <source>Choose a square, single-view SVG source</source>
            <translation>正方形で単一ビューの SVG ソースを選んでください</translation>
        </message>
        <message>
            <source>Select disjoint groups for depth; clear the parent or child depth first</source>
            <translation>深度には重ならないグループを選んでください。先に親または子の深度をゼロにしてください</translation>
        </message>
        <message>
            <source>Singular parent transform for </source>
            <translation>親の変換が逆変換できません: </translation>
        </message>
        <message>
            <source>Cannot render the authored view</source>
            <translation>作成したビューを描画できません</translation>
        </message>
        <message>
            <source>Cannot encode pair</source>
            <translation>ペアをエンコードできません</translation>
        </message>
        <message>
            <source>The views have different dimensions</source>
            <translation>ビューの寸法が異なります</translation>
        </message>
        <message>
            <source>Cannot encode PNG</source>
            <translation>PNG をエンコードできません</translation>
        </message>
        <message>
            <source>the desktop's limit is zero</source>
            <translation>デスクトップの制限がゼロです</translation>
        </message>
        <message>
            <source>no room in the drawing at this size</source>
            <translation>このサイズでは描画内に移動する余地がありません</translation>
        </message>
        <message>
            <source>Depth order cannot fit in this drawing at %1 px: %2 / %3</source>
            <translation>%1 px ではこの描画内の奥行き順序を維持できません: %2 / %3</translation>
        </message>
    </context>
    <context>
        <name>Editor</name>
        <message>
            <source>Open icon theme…</source>
            <translation>アイコンテーマを開く…</translation>
        </message>
        <message>
            <source>Save a project copy…</source>
            <translation>プロジェクトのコピーを保存…</translation>
        </message>
        <message>
            <source>Undo</source>
            <translation>元に戻す</translation>
        </message>
        <message>
            <source>Redo</source>
            <translation>やり直す</translation>
        </message>
        <message>
            <source>Icons</source>
            <translation>アイコン</translation>
        </message>
        <message>
            <source>Enable 3D</source>
            <translation>3D を有効にする</translation>
        </message>
        <message>
            <source>Pixels per view: </source>
            <translation>ビューあたりのピクセル数: </translation>
        </message>
        <message>
            <source>Display Settings…</source>
            <translation>ディスプレイ設定…</translation>
        </message>
        <message>
            <source>Open a theme. Save creates a separate project copy.</source>
            <translation>テーマを開いてください。保存すると、別のプロジェクトコピーが作成されます。</translation>
        </message>
        <message>
            <source>Part</source>
            <translation>パーツ</translation>
        </message>
        <message>
            <source>Depth (% of limit)</source>
            <translation>深度（上限に対する %）</translation>
        </message>
        <message>
            <source>Select a part to highlight it in both views. Negative depth sinks; positive depth pops.</source>
            <translation>パーツを選ぶと、両方のビューで強調表示されます。負の深度は奥へ、正の深度は手前へ移動します。</translation>
        </message>
        <message>
            <source>Size per view</source>
            <translation>ビューのサイズ</translation>
        </message>
        <message>
            <source>Disparity</source>
            <translation>視差</translation>
        </message>
        <message>
            <source>Icon theme folder</source>
            <translation>アイコンテーマのフォルダー</translation>
        </message>
        <message>
            <source>SVG source</source>
            <translation>SVG ソース</translation>
        </message>
        <message>
            <source>New project folder</source>
            <translation>新しいプロジェクトフォルダー</translation>
        </message>
        <message>
            <source>Display Settings</source>
            <translation>ディスプレイ設定</translation>
        </message>
        <message>
            <source>Cannot start Display Settings (kcmshell6).</source>
            <translation>ディスプレイ設定を起動できません（kcmshell6）。</translation>
        </message>
        <message>
            <source>Cannot complete the operation</source>
            <translation>操作を完了できません</translation>
        </message>
        <message>
            <source>Choose an icon inside a readable theme with index.theme</source>
            <translation>index.theme を含む読み取り可能なテーマ内のアイコンを選んでください</translation>
        </message>
        <message>
            <source> %</source>
            <translation> %</translation>
        </message>
        <message>
            <source>Depth of %1</source>
            <translation>%1 の深度</translation>
        </message>
        <message>
            <source>Read only source: %1. Save creates a separate project copy.</source>
            <translation>読み取り専用ソース: %1。保存すると、別のプロジェクトコピーが作成されます。</translation>
        </message>
        <message>
            <source>Selected: %1 (%2)</source>
            <translation>選択: %1（%2）</translation>
        </message>
        <message>
            <source>Sunk</source>
            <translation>奥</translation>
        </message>
        <message>
            <source>Popped</source>
            <translation>手前</translation>
        </message>
        <message>
            <source>Screen</source>
            <translation>画面の平面</translation>
        </message>
        <message>
            <source>%1 px</source>
            <translation>%1 px</translation>
        </message>
        <message>
            <source>0 px (screen)</source>
            <translation>0 px（画面の平面）</translation>
        </message>
        <message>
            <source>A group depth must be a number</source>
            <translation>グループの深度には数値を指定してください</translation>
        </message>
        <message>
            <source>Unsaved changes</source>
            <translation>未保存の変更</translation>
        </message>
        <message>
            <source>Discard unsaved changes?</source>
            <translation>未保存の変更を破棄しますか？</translation>
        </message>
        <message>
            <source>Close the KDE tool before closing this project.</source>
            <translation>このプロジェクトを閉じる前に KDE ツールを閉じてください。</translation>
        </message>
        <message>
            <source>Invalid group or place</source>
            <translation>グループまたは位置が無効です</translation>
        </message>
        <message>
            <source>Cannot read the project</source>
            <translation>プロジェクトを読み取れません</translation>
        </message>
        <message>
            <source>Invalid or unsupported theme project</source>
            <translation>テーマプロジェクトが無効か未対応です</translation>
        </message>
        <message>
            <source>Project copy: %1</source>
            <translation>プロジェクトのコピー: %1</translation>
        </message>
        <message>
            <source>Open a source first</source>
            <translation>先にソースを開いてください</translation>
        </message>
        <message>
            <source>The project destination already exists; choose a new folder</source>
            <translation>保存先は既に存在します。新しいフォルダーを選んでください</translation>
        </message>
        <message>
            <source>Save the copy outside its source theme</source>
            <translation>コピーは元のテーマの外に保存してください</translation>
        </message>
        <message>
            <source>Cannot create the project beside its destination</source>
            <translation>保存先の隣にプロジェクトを作成できません</translation>
        </message>
        <message>
            <source>A project index must be a regular file</source>
            <translation>プロジェクトのインデックスは通常のファイルである必要があります</translation>
        </message>
        <message>
            <source>Cannot make the copied index writable</source>
            <translation>コピーしたインデックスを書き込み可能にできません</translation>
        </message>
        <message>
            <source>Declared icon size exceeds the supported 2048 pixels per view</source>
            <translation>宣言されたアイコンのサイズが、対応する上限のビューあたり 2048 ピクセルを超えています</translation>
        </message>
        <message>
            <source>Choose an SVG source inside a context declared in index.theme</source>
            <translation>index.theme で宣言されたコンテキスト内の SVG ソースを選んでください</translation>
        </message>
        <message>
            <source>The theme declares no usable sizes</source>
            <translation>テーマに使用可能なサイズが宣言されていません</translation>
        </message>
        <message>
            <source>Cannot save the copied theme index</source>
            <translation>コピーしたテーマのインデックスを保存できません</translation>
        </message>
        <message>
            <source>Cannot commit the project folder</source>
            <translation>プロジェクトフォルダーの保存を確定できません</translation>
        </message>
        <message>
            <source>Saved project copy: %1</source>
            <translation>プロジェクトのコピーを保存しました: %1</translation>
        </message>
        <message>
            <source>The colour scheme is too large</source>
            <translation>配色のサイズが大きすぎます</translation>
        </message>
        <message>
            <source>Open colour scheme…</source>
            <translation>配色を開く…</translation>
        </message>
        <message>
            <source>Edit colours in KDE…</source>
            <translation>KDE で色を編集…</translation>
        </message>
        <message>
            <source>Open Plasma SVG part…</source>
            <translation>Plasma の SVG パーツを開く…</translation>
        </message>
        <message>
            <source>Explore Plasma theme…</source>
            <translation>Plasma テーマを閲覧…</translation>
        </message>
        <message>
            <source>No colour scheme in this project</source>
            <translation>このプロジェクトに配色はありません</translation>
        </message>
        <message>
            <source>Colour scheme</source>
            <translation>配色</translation>
        </message>
        <message>
            <source>Plasma theme folder</source>
            <translation>Plasma テーマのフォルダー</translation>
        </message>
        <message>
            <source>Choose an SVG inside a Plasma theme with metadata.json</source>
            <translation>metadata.json がある Plasma テーマ内の SVG を選んでください</translation>
        </message>
        <message>
            <source>Plasma parts</source>
            <translation>Plasma パーツ</translation>
        </message>
        <message>
            <source>Cannot inspect the colour scheme</source>
            <translation>配色を確認できません</translation>
        </message>
        <message>
            <source>Not a KDE colour scheme</source>
            <translation>KDE の配色ではありません</translation>
        </message>
        <message>
            <source>The colour scheme has no name</source>
            <translation>配色に名前がありません</translation>
        </message>
        <message>
            <source>Colour scheme: %1. KDE edits a private copy; Save keeps it in this project.</source>
            <translation>配色: %1。KDE で専用コピーを編集し、保存するとこのプロジェクトに保持されます。</translation>
        </message>
        <message>
            <source>Close the KDE tool before opening another one.</source>
            <translation>別の KDE ツールを開く前に、現在のツールを閉じてください。</translation>
        </message>
        <message>
            <source>Cannot create a private working copy</source>
            <translation>専用の作業コピーを作成できません</translation>
        </message>
        <message>
            <source>The KDE tool failed: %1</source>
            <translation>KDE ツールが失敗しました: %1</translation>
        </message>
        <message>
            <source>The KDE tool returned an invalid file name</source>
            <translation>KDE ツールが無効なファイル名を返しました</translation>
        </message>
        <message>
            <source>Cannot start %1: %2</source>
            <translation>%1 を起動できません: %2</translation>
        </message>
        <message>
            <source>Open a colour scheme first</source>
            <translation>最初に配色を開いてください</translation>
        </message>
        <message>
            <source>The Plasma working copy contains an outside or cyclic link: %1</source>
            <translation>Plasma の作業コピーにテーマ外へのリンクまたは循環リンクがあります: %1</translation>
        </message>
        <message>
            <source>Open a Plasma theme part first</source>
            <translation>最初に Plasma テーマのパーツを開いてください</translation>
        </message>
        <message>
            <source>The Plasma theme has no valid identifier</source>
            <translation>Plasma テーマに有効な識別子がありません</translation>
        </message>
        <message>
            <source>About…</source>
            <translation>このソフトウェアについて…</translation>
        </message>
        <message>
            <source>Cannot read the preview output</source>
            <translation>プレビュー出力を読み取れません</translation>
        </message>
        <message>
            <source>Export (defaults)</source>
            <translation>書き出し (既定値)</translation>
        </message>
        <message>
            <source>Preview (desktop)</source>
            <translation>プレビュー (デスクトップ)</translation>
        </message>
        <message>
            <source>0 px (%1)</source>
            <translation>0 px (%1)</translation>
        </message>
        <message>
            <source>; same pixel as %1</source>
            <translation>; %1 と同じピクセル</translation>
        </message>
        <message>
            <source>Models</source>
            <translation>モデル</translation>
        </message>
        <message>
            <source>Open model…</source>
            <translation>モデルを開く…</translation>
        </message>
        <message>
            <source>Open a glTF model. The source is read only.</source>
            <translation>glTFモデルを開きます。元のファイルは読み取り専用です。</translation>
        </message>
        <message>
            <source>Export model pairs…</source>
            <translation>モデルのペアを書き出す…</translation>
        </message>
        <message>
            <source>Cannot read model: %1</source>
            <translation>モデルを読み取れません: %1</translation>
        </message>
        <message>
            <source>Cannot create model render files.</source>
            <translation>モデルの描画ファイルを作成できません。</translation>
        </message>
        <message>
            <source>Cannot start the model renderer. Install the model helper and its dependencies.</source>
            <translation>モデルの描画を開始できません。モデル用ヘルパーと依存パッケージをインストールしてください。</translation>
        </message>
        <message>
            <source>The model renderer did not finish.</source>
            <translation>モデルの描画が完了しませんでした。</translation>
        </message>
        <message>
            <source>Cannot render model: %1</source>
            <translation>モデルを描画できません: %1</translation>
        </message>
        <message>
            <source>The model renderer returned invalid data.</source>
            <translation>モデルの描画で無効なデータが返されました。</translation>
        </message>
        <message>
            <source>Choose a readable glTF (.gltf or .glb) model.</source>
            <translation>読み取り可能なglTFモデル（.gltfまたは.glb）を選択してください。</translation>
        </message>
        <message>
            <source>Read only model: %1</source>
            <translation>読み取り専用モデル: %1</translation>
        </message>
        <message>
            <source>%1 px: far / near %2; preview %3</source>
            <translation>%1 px: 遠点 / 近点 %2、プレビュー %3</translation>
        </message>
        <message>
            <source>Model assets must be local files beside the glTF model.</source>
            <translation>モデルの素材はglTFモデルと同じ場所にあるローカルファイルである必要があります。</translation>
        </message>
        <message>
            <source>The model helper is unavailable in this build.</source>
            <translation>このビルドではモデル用ヘルパーを利用できません。</translation>
        </message>
        <message>
            <source>the desktop's limit is zero</source>
            <translation>デスクトップの上限はゼロです</translation>
        </message>
        <message>
            <source>no room in the drawing at this size</source>
            <translation>このサイズでは描画内に余地がありません</translation>
        </message>
    </context>
    <context>
        <name>Identity</name>
        <message>
            <source>Product name</source>
            <translation>@PRODUCT@</translation>
        </message>
    </context>
</TS>
