import re,sys
p='player/command.c'; s=open(p).read()
old=s[s.index('// Keep the correction in the CLI\'s existing per-file playback state.'):s.index('static void cmd_run(void *p)')]
new='''// Store the effective swap of the eyes of the playing file with the file (user.stereo-policy.swap-eyes), so that the
// correction is kept with it; the session's swap then reads as no change. This is the only place that writes the file,
// and only on this command: the swap property keeps the person's choice in the per-file playback state alone. Once the
// file carries the correction, the per-file mark is unmarked again.
static void cmd_video_stereo_store_swap(void *p)
{
    struct mp_cmd_ctx *cmd = p;
    struct MPContext *mpctx = cmd->mpctx;

#if HAVE_STEREO_POLICY
    struct filter_opts *fopts = mp_get_config_group(NULL, mpctx->global, &filter_conf);
    bool swap = fopts->video_stereo_swap != fopts->video_stereo_swap_file;
    talloc_free(fopts);

    char *path = mpctx->filename;
    if (path && !mp_is_url(bstr0(path)) && stereo_policy_set_file_swap_eyes(path, swap) == 0) {
        m_config_set_option_cli(mpctx->mconfig, bstr0("video-stereo-swap-file"), bstr0(swap ? "yes" : "no"), 0);
        m_config_set_option_cli(mpctx->mconfig, bstr0("video-stereo-swap"), bstr0("no"), 0);
        if (mpctx->is_cli && mpctx->playing)
            mp_write_watch_later_conf(mpctx);
        return;
    }
#endif
    cmd->success = false;
}

'''
s=s.replace(old,new); open(p,'w').write(s)
