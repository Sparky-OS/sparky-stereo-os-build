/* Copyright 2026 Daniel Campos Ramos. SPDX-License-Identifier: MIT */
/* What the library says when the GPU chosen for players cannot decode a video, in the edition's nine languages
 * (en, pl, pt_BR, fr, de, ja, ko, zh_CN, zh_TW). A library does not own its program's locale, so the language comes
 * from the environment, as gettext's does; the table needs no files. Drafted with AI assistance; native review welcome. */
#include "gpu-private.h"
#include <stdlib.h>
#include <string.h>

static const char *const languages[] = { "en", "pl", "pt_BR", "fr", "de", "ja", "ko", "zh_CN", "zh_TW" };

static const char *const texts[][9] = {
    [MEDIA_GPU_TEXT_PAGE_FAILED] = {
        "the GPU chosen for players in System Settings, Graphics could not be resolved (sparky-stereo-gpu-env exit status %d). This video is decoded in software, on no other GPU.",
        "nie udało się ustalić procesora graficznego wybranego dla odtwarzaczy w Ustawieniach systemowych, Grafika (kod wyjścia sparky-stereo-gpu-env %d). To wideo jest dekodowane programowo, na żadnym innym procesorze graficznym.",
        "não foi possível determinar a GPU escolhida para os reprodutores em Configurações do Sistema, Gráficos (código de saída do sparky-stereo-gpu-env %d). Este vídeo é decodificado em software, em nenhuma outra GPU.",
        "le GPU choisi pour les lecteurs dans Configuration du système, Graphiques n'a pas pu être déterminé (code de sortie de sparky-stereo-gpu-env %d). Cette vidéo est décodée par logiciel, sur aucun autre GPU.",
        "die in den Systemeinstellungen unter Grafik für Player gewählte GPU konnte nicht ermittelt werden (Exit-Status von sparky-stereo-gpu-env %d). Dieses Video wird in Software dekodiert, auf keiner anderen GPU.",
        "システム設定の「グラフィックス」でプレーヤー用に選んだGPUを特定できませんでした (sparky-stereo-gpu-env の終了ステータス %d)。この動画はソフトウェアでデコードし、他のGPUは使いません。",
        "시스템 설정의 그래픽에서 플레이어용으로 선택한 GPU를 확인하지 못했습니다(sparky-stereo-gpu-env 종료 상태 %d). 이 동영상은 소프트웨어로 디코딩하며 다른 GPU는 사용하지 않습니다.",
        "无法确定在“系统设置 > 图形”中为播放器选择的 GPU（sparky-stereo-gpu-env 退出状态 %d）。此视频以软件解码，不使用其他 GPU。",
        "無法確定在「系統設定 > 圖形」中為播放器選擇的 GPU（sparky-stereo-gpu-env 結束狀態 %d）。此影片以軟體解碼，不使用其他 GPU。",
    },
    [MEDIA_GPU_TEXT_NOT_FOUND] = {
        "the GPU chosen for players in System Settings, Graphics (%s) is not among the GPUs this program can open. This video is decoded in software, on no other GPU.",
        "procesora graficznego wybranego dla odtwarzaczy w Ustawieniach systemowych, Grafika (%s) nie ma wśród procesorów graficznych, które ten program może otworzyć. To wideo jest dekodowane programowo, na żadnym innym procesorze graficznym.",
        "a GPU escolhida para os reprodutores em Configurações do Sistema, Gráficos (%s) não está entre as GPUs que este programa pode abrir. Este vídeo é decodificado em software, em nenhuma outra GPU.",
        "le GPU choisi pour les lecteurs dans Configuration du système, Graphiques (%s) ne fait pas partie des GPU que ce programme peut ouvrir. Cette vidéo est décodée par logiciel, sur aucun autre GPU.",
        "die in den Systemeinstellungen unter Grafik für Player gewählte GPU (%s) ist nicht unter den GPUs, die dieses Programm öffnen kann. Dieses Video wird in Software dekodiert, auf keiner anderen GPU.",
        "システム設定の「グラフィックス」でプレーヤー用に選んだGPU (%s) は、このプログラムが開けるGPUの中にありません。この動画はソフトウェアでデコードし、他のGPUは使いません。",
        "시스템 설정의 그래픽에서 플레이어용으로 선택한 GPU(%s)가 이 프로그램이 열 수 있는 GPU 중에 없습니다. 이 동영상은 소프트웨어로 디코딩하며 다른 GPU는 사용하지 않습니다.",
        "在“系统设置 > 图形”中为播放器选择的 GPU（%s）不在此程序可以打开的 GPU 之中。此视频以软件解码，不使用其他 GPU。",
        "在「系統設定 > 圖形」中為播放器選擇的 GPU（%s）不在此程式可以開啟的 GPU 之中。此影片以軟體解碼，不使用其他 GPU。",
    },
    [MEDIA_GPU_TEXT_CANNOT_DECODE] = {
        "the GPU chosen for players, %s, cannot decode this video in hardware. It is decoded in software; to decode it on another GPU instead, turn on Decode on another GPU in System Settings, Graphics.",
        "procesor graficzny wybrany dla odtwarzaczy, %s, nie może sprzętowo dekodować tego wideo. Jest ono dekodowane programowo; aby zamiast tego dekodować je na innym procesorze graficznym, włącz Dekoduj na innym procesorze graficznym w Ustawieniach systemowych, Grafika.",
        "a GPU escolhida para os reprodutores, %s, não consegue decodificar este vídeo em hardware. Ele é decodificado em software; para decodificá-lo em outra GPU, ative Decodificar em outra GPU em Configurações do Sistema, Gráficos.",
        "le GPU choisi pour les lecteurs, %s, ne peut pas décoder cette vidéo matériellement. Elle est décodée par logiciel ; pour la décoder plutôt sur un autre GPU, activez Décoder sur un autre GPU dans Configuration du système, Graphiques.",
        "die für Player gewählte GPU, %s, kann dieses Video nicht in Hardware dekodieren. Es wird in Software dekodiert; um es stattdessen auf einer anderen GPU zu dekodieren, schalten Sie in den Systemeinstellungen unter Grafik „Auf einer anderen GPU dekodieren“ ein.",
        "プレーヤー用に選んだGPU %s は、この動画をハードウェアでデコードできません。ソフトウェアでデコードします。代わりに別のGPUでデコードするには、システム設定の「グラフィックス」で「別のGPUでデコード」をオンにしてください。",
        "플레이어용으로 선택한 GPU %s은(는) 이 동영상을 하드웨어로 디코딩할 수 없습니다. 소프트웨어로 디코딩합니다. 대신 다른 GPU에서 디코딩하려면 시스템 설정의 그래픽에서 '다른 GPU에서 디코딩'을 켜십시오.",
        "为播放器选择的 GPU %s 无法以硬件解码此视频。此视频以软件解码；要改为在另一个 GPU 上解码，请在“系统设置 > 图形”中打开“在另一个 GPU 上解码”。",
        "為播放器選擇的 GPU %s 無法以硬體解碼此影片。此影片以軟體解碼；要改為在另一個 GPU 上解碼，請在「系統設定 > 圖形」中開啟「在另一個 GPU 上解碼」。",
    },
    [MEDIA_GPU_TEXT_OTHER_GPU] = {
        "the GPU chosen for players cannot decode this video in hardware, so it is decoded on %s, as Decode on another GPU allows.",
        "procesor graficzny wybrany dla odtwarzaczy nie może sprzętowo dekodować tego wideo, więc jest ono dekodowane na %s, na co pozwala Dekoduj na innym procesorze graficznym.",
        "a GPU escolhida para os reprodutores não consegue decodificar este vídeo em hardware, então ele é decodificado em %s, como Decodificar em outra GPU permite.",
        "le GPU choisi pour les lecteurs ne peut pas décoder cette vidéo matériellement : elle est donc décodée sur %s, comme Décoder sur un autre GPU le permet.",
        "die für Player gewählte GPU kann dieses Video nicht in Hardware dekodieren, daher wird es auf %s dekodiert, wie „Auf einer anderen GPU dekodieren“ es erlaubt.",
        "プレーヤー用に選んだGPUはこの動画をハードウェアでデコードできないため、「別のGPUでデコード」の設定どおり %s でデコードします。",
        "플레이어용으로 선택한 GPU가 이 동영상을 하드웨어로 디코딩할 수 없어, '다른 GPU에서 디코딩'이 허용하는 대로 %s에서 디코딩합니다.",
        "为播放器选择的 GPU 无法以硬件解码此视频，因此按照“在另一个 GPU 上解码”的允许，在 %s 上解码。",
        "為播放器選擇的 GPU 無法以硬體解碼此影片，因此依照「在另一個 GPU 上解碼」的允許，在 %s 上解碼。",
    },
    [MEDIA_GPU_TEXT_UNKNOWN] = {
        "the GPU chosen for players, %s, could not be asked what it decodes: its VA-API or NVDEC driver did not answer. This video is decoded in software, on no other GPU.",
        "nie udało się zapytać procesora graficznego wybranego dla odtwarzaczy, %s, co dekoduje: jego sterownik VA-API lub NVDEC nie odpowiedział. To wideo jest dekodowane programowo, na żadnym innym procesorze graficznym.",
        "não foi possível perguntar à GPU escolhida para os reprodutores, %s, o que ela decodifica: o driver VA-API ou NVDEC dela não respondeu. Este vídeo é decodificado em software, em nenhuma outra GPU.",
        "le GPU choisi pour les lecteurs, %s, n'a pas pu indiquer ce qu'il décode : son pilote VA-API ou NVDEC n'a pas répondu. Cette vidéo est décodée par logiciel, sur aucun autre GPU.",
        "die für Player gewählte GPU, %s, konnte nicht gefragt werden, was sie dekodiert: ihr VA-API- oder NVDEC-Treiber hat nicht geantwortet. Dieses Video wird in Software dekodiert, auf keiner anderen GPU.",
        "プレーヤー用に選んだGPU %s に、何をデコードできるかを問い合わせられませんでした。VA-API または NVDEC のドライバーが応答しませんでした。この動画はソフトウェアでデコードし、他のGPUは使いません。",
        "플레이어용으로 선택한 GPU %s에 무엇을 디코딩할 수 있는지 물어보지 못했습니다. VA-API 또는 NVDEC 드라이버가 응답하지 않았습니다. 이 동영상은 소프트웨어로 디코딩하며 다른 GPU는 사용하지 않습니다.",
        "无法询问为播放器选择的 GPU %s 能解码什么：它的 VA-API 或 NVDEC 驱动程序没有响应。此视频以软件解码，不使用其他 GPU。",
        "無法詢問為播放器選擇的 GPU %s 能解碼什麼：它的 VA-API 或 NVDEC 驅動程式沒有回應。此影片以軟體解碼，不使用其他 GPU。",
    },
    [MEDIA_GPU_TEXT_COPY_BACK_OFF] = {
        "Decoding in software: this video's conversion needs the decoded pictures in memory, and copying them back from the GPU is off. To copy them back instead, turn on Copy decoded video back in System Settings, Graphics, or choose a copying decoder in the player.",
        "Dekodowanie programowe: konwersja tego wideo potrzebuje zdekodowanych obrazów w pamięci, a kopiowanie ich z powrotem z procesora graficznego jest wyłączone. Aby zamiast tego je kopiować, włącz Kopiuj zdekodowane wideo z powrotem w Ustawieniach systemowych, Grafika, albo wybierz w odtwarzaczu dekoder, który kopiuje.",
        "Decodificando em software: a conversão deste vídeo precisa das imagens decodificadas na memória, e copiá-las de volta da GPU está desligado. Para copiá-las de volta, ative Copiar o vídeo decodificado de volta em Configurações do Sistema, Gráficos, ou escolha no reprodutor um decodificador que copia.",
        "Décodage par logiciel : la conversion de cette vidéo a besoin des images décodées en mémoire, et leur recopie depuis le GPU est désactivée. Pour les recopier plutôt, activez Recopier la vidéo décodée dans Configuration du système, Graphiques, ou choisissez dans le lecteur un décodeur qui recopie.",
        "Dekodierung in Software: Die Umwandlung dieses Videos braucht die dekodierten Bilder im Speicher, und das Zurückkopieren von der GPU ist aus. Um sie stattdessen zurückzukopieren, schalten Sie in den Systemeinstellungen unter Grafik „Dekodiertes Video zurückkopieren“ ein oder wählen Sie im Player einen kopierenden Decoder.",
        "ソフトウェアでデコードしています: この動画の変換にはデコードした画像がメモリー上に必要ですが、GPUからのコピーバックはオフです。代わりにコピーバックするには、システム設定の「グラフィックス」で「デコードした動画をコピーして戻す」をオンにするか、プレーヤーでコピーするデコーダーを選んでください。",
        "소프트웨어로 디코딩 중: 이 동영상의 변환에는 디코딩한 이미지가 메모리에 있어야 하는데, GPU에서 다시 복사해 오는 것이 꺼져 있습니다. 대신 다시 복사해 오려면 시스템 설정의 그래픽에서 '디코딩한 비디오를 다시 복사'를 켜거나, 플레이어에서 복사하는 디코더를 선택하십시오.",
        "正在以软件解码：此视频的转换需要内存中的解码画面，而从 GPU 复制回来的功能已关闭。要改为复制回来，请在“系统设置 > 图形”中打开“将解码的视频复制回来”，或在播放器中选择会复制的解码器。",
        "正在以軟體解碼：此影片的轉換需要記憶體中的解碼畫面，而從 GPU 複製回來的功能已關閉。要改為複製回來，請在「系統設定 > 圖形」中開啟「將解碼的視訊複製回來」，或在播放器中選擇會複製的解碼器。",
    },
};

const char *media_gpu_route_language(void)
{
    /* gettext's order: LANGUAGE (its first entry), then LC_ALL, LC_MESSAGES and LANG */
    const char *names[] = { "LANGUAGE", "LC_ALL", "LC_MESSAGES", "LANG" };
    for (size_t n = 0; n < sizeof(names) / sizeof(names[0]); n++) {
        const char *value = getenv(names[n]);
        if (!value || !*value)
            continue;
        char lang[32];
        size_t length = strcspn(value, ":.@");
        if (length >= sizeof(lang))
            length = sizeof(lang) - 1;
        memcpy(lang, value, length);
        lang[length] = 0;
        if (!strcmp(lang, "C") || !strcmp(lang, "POSIX"))
            return "en";
        if (!strncmp(lang, "zh", 2))
            return !strcmp(lang, "zh_TW") || !strcmp(lang, "zh_HK") ? "zh_TW" : "zh_CN";
        for (size_t i = 0; i < sizeof(languages) / sizeof(languages[0]); i++)
            if (!strcmp(lang, languages[i]))
                return languages[i];
        lang[strcspn(lang, "_")] = 0;
        for (size_t i = 0; i < sizeof(languages) / sizeof(languages[0]); i++)
            if (!strcmp(lang, languages[i]))
                return languages[i];
        return "en";
    }
    return "en";
}

const char *media_gpu_route_copy_back_off_text(void)
{
    return media_gpu_route_text(MEDIA_GPU_TEXT_COPY_BACK_OFF);
}

const char *media_gpu_route_text(enum media_gpu_text text)
{
    const char *lang = media_gpu_route_language();
    for (size_t i = 0; i < sizeof(languages) / sizeof(languages[0]); i++)
        if (!strcmp(lang, languages[i]))
            return texts[text][i];
    return texts[text][0];
}
