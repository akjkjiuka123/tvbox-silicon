#include "TVMedia.h"

#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavutil/audio_fifo.h>
#include <libavutil/dovi_meta.h>
#include <libavutil/intreadwrite.h>
#include <libavutil/opt.h>
#include <libavutil/pixdesc.h>
#include <libswresample/swresample.h>
#include <libswscale/swscale.h>
#include <stdio.h>
#include <string.h>

/// How far before a keyframe's time a packet still counts as that keyframe (index times are rounded).
#define TOLERANCE 2000
/// A track with nothing past the segment's end stops being waited for once the reader is this far beyond it.
#define LOOKAHEAD 3000000
/// Each segment goes out in fragments of about this length, so its first bytes leave before it is finished.
#define FRAGMENT 1000000
/// Copied video ends its segment at the next keyframe; the reader gives up on one this far past the end.
#define MAXGOP 60000000
/// Beyond the keyframe index by this much, a seek guesses a byte position instead of reading up to the time.
#define UNINDEXED 30000000

static TVMLogFunction logger;

static void log_callback(void *object, int level, const char *format, va_list arguments) {
    if (!logger || level > AV_LOG_WARNING) return;
    char line[1024];
    int prefix = 1;
    av_log_format_line(object, level, format, arguments, line, sizeof line, &prefix);
    size_t length = strlen(line);
    while (length > 0 && (line[length - 1] == '\n' || line[length - 1] == '\r')) line[--length] = 0;
    if (length > 0) logger(level, line);
}

void tvm_set_log(TVMLogFunction log) {
    logger = log;
    av_log_set_level(AV_LOG_WARNING);
    av_log_set_callback(log_callback);
}

static int fail(char *error, int size, int code, const char *what) {
    if (error && size > 0) {
        char reason[AV_ERROR_MAX_STRING_SIZE] = {0};
        av_strerror(code, reason, sizeof reason);
        snprintf(error, size, "%s: %s", what, reason);
    }
    return code;
}

// MARK: - Input

struct TVMInput {
    AVFormatContext *format;
    AVIOContext *io;
    void *context;
    TVMReadFunction read;
    TVMInterruptFunction interrupted;
    int64_t size, position;
};

static int input_read(void *opaque, uint8_t *buffer, int size) {
    TVMInput *input = opaque;
    if (input->size >= 0 && input->position >= input->size) return AVERROR_EOF;
    int count = input->read(input->context, input->position, buffer, size);
    if (count == 0) return AVERROR_EOF;
    if (count < 0) return input->interrupted && input->interrupted(input->context) ? AVERROR_EXIT : AVERROR(EIO);
    input->position += count;
    return count;
}

static int64_t input_seek(void *opaque, int64_t offset, int whence) {
    TVMInput *input = opaque;
    switch (whence & ~AVSEEK_FORCE) {
    case AVSEEK_SIZE: return input->size >= 0 ? input->size : AVERROR(ENOSYS);
    case SEEK_SET: input->position = offset; break;
    case SEEK_CUR: input->position += offset; break;
    case SEEK_END:
        if (input->size < 0) return AVERROR(ENOSYS);
        input->position = input->size + offset;
        break;
    default: return AVERROR(EINVAL);
    }
    return input->position;
}

static int input_interrupt(void *opaque) {
    TVMInput *input = opaque;
    return input->interrupted ? input->interrupted(input->context) : 0;
}

TVMInput *tvm_open(void *context, TVMReadFunction read, TVMInterruptFunction interrupted, int64_t size,
                   char *error, int errorSize) {
    TVMInput *input = av_mallocz(sizeof(TVMInput));
    if (!input) { fail(error, errorSize, AVERROR(ENOMEM), "open"); return NULL; }
    input->context = context; input->read = read; input->interrupted = interrupted; input->size = size;
    const int bufferSize = 256 << 10;
    uint8_t *buffer = av_malloc(bufferSize);
    input->io = buffer ? avio_alloc_context(buffer, bufferSize, 0, input, input_read, NULL, size >= 0 ? input_seek : NULL) : NULL;
    if (!input->io) { av_free(buffer); av_free(input); fail(error, errorSize, AVERROR(ENOMEM), "open"); return NULL; }
    input->io->seekable = size >= 0 ? AVIO_SEEKABLE_NORMAL : 0;
    AVFormatContext *format = avformat_alloc_context();
    if (!format) { tvm_close(input); fail(error, errorSize, AVERROR(ENOMEM), "open"); return NULL; }
    format->pb = input->io;
    // GENPTS: AVI and FLV store decode times only; the MP4 muxer needs presentation times as well.
    format->flags |= AVFMT_FLAG_CUSTOM_IO | AVFMT_FLAG_GENPTS;
    format->interrupt_callback.callback = input_interrupt;
    format->interrupt_callback.opaque = input;
    // Enough to learn every stream's parameters without reading far into a remote file.
    format->probesize = 4 << 20;
    format->max_analyze_duration = 2 * AV_TIME_BASE;
    int status = avformat_open_input(&format, NULL, NULL, NULL);
    if (status < 0) { tvm_close(input); fail(error, errorSize, status, "open"); return NULL; }
    input->format = format;
    status = avformat_find_stream_info(format, NULL);
    if (status < 0) { tvm_close(input); fail(error, errorSize, status, "stream info"); return NULL; }
    // Matroska reads its Cues (the keyframe index) at the first seek; back to the start does it now.
    if (size >= 0) av_seek_frame(format, -1, format->start_time == AV_NOPTS_VALUE ? 0 : format->start_time, AVSEEK_FLAG_BACKWARD);
    return input;
}

void tvm_close(TVMInput *input) {
    if (!input) return;
    if (input->format) avformat_close_input(&input->format);
    if (input->io) { av_freep(&input->io->buffer); avio_context_free(&input->io); }
    av_free(input);
}

const char *tvm_format(const TVMInput *input) { return input->format->iformat->name; }

int64_t tvm_duration(const TVMInput *input) {
    return input->format->duration == AV_NOPTS_VALUE ? -1 : input->format->duration;
}

int64_t tvm_start_time(const TVMInput *input) {
    return input->format->start_time == AV_NOPTS_VALUE ? 0 : input->format->start_time;
}

int tvm_stream_count(const TVMInput *input) { return (int)input->format->nb_streams; }

static int64_t microseconds(int64_t value, AVRational base) {
    return value == AV_NOPTS_VALUE ? -1 : av_rescale_q(value, base, AV_TIME_BASE_Q);
}

int tvm_stream(const TVMInput *input, int index, TVMStream *out) {
    if (index < 0 || index >= (int)input->format->nb_streams) return -1;
    const AVStream *st = input->format->streams[index];
    const AVCodecParameters *par = st->codecpar;
    memset(out, 0, sizeof *out);
    switch (par->codec_type) {
    case AVMEDIA_TYPE_VIDEO: out->kind = st->disposition & AV_DISPOSITION_ATTACHED_PIC ? TVMKindOther : TVMKindVideo; break;
    case AVMEDIA_TYPE_AUDIO: out->kind = TVMKindAudio; break;
    case AVMEDIA_TYPE_SUBTITLE: out->kind = TVMKindSubtitle; break;
    default: out->kind = TVMKindOther; break;
    }
    snprintf(out->codec, sizeof out->codec, "%s", avcodec_get_name(par->codec_id));
    out->profile = par->profile; out->level = par->level;
    out->width = par->width; out->height = par->height;
    if (par->codec_type == AVMEDIA_TYPE_VIDEO) {
        const AVPixFmtDescriptor *pixels = av_pix_fmt_desc_get(par->format);
        if (pixels) {
            out->bitDepth = pixels->comp[0].depth;
            if (pixels->nb_components >= 3)
                out->chroma = pixels->log2_chroma_w == 1 ? (pixels->log2_chroma_h == 1 ? 420 : 422) : (pixels->log2_chroma_h == 0 ? 444 : 0);
        } else out->bitDepth = par->bits_per_raw_sample;
        AVRational rate = st->avg_frame_rate.num && st->avg_frame_rate.den ? st->avg_frame_rate : st->r_frame_rate;
        out->frameRate = rate.num && rate.den ? av_q2d(rate) : 0;
        AVRational aspect = par->sample_aspect_ratio.num ? par->sample_aspect_ratio : st->sample_aspect_ratio;
        out->sampleAspectNum = aspect.num; out->sampleAspectDen = aspect.den;
        out->colorTransfer = par->color_trc; out->colorPrimaries = par->color_primaries;
    }
    out->doviProfile = out->doviLevel = out->doviCompatibility = -1;
    const AVPacketSideData *dovi = av_packet_side_data_get(par->coded_side_data, par->nb_coded_side_data, AV_PKT_DATA_DOVI_CONF);
    if (dovi && dovi->size >= sizeof(AVDOVIDecoderConfigurationRecord)) {
        const AVDOVIDecoderConfigurationRecord *record = (const AVDOVIDecoderConfigurationRecord *)dovi->data;
        out->doviProfile = record->dv_profile; out->doviLevel = record->dv_level;
        out->doviCompatibility = record->dv_bl_signal_compatibility_id;
    }
    out->sampleRate = par->sample_rate;
    out->channels = par->ch_layout.nb_channels;
    out->bitRate = par->bit_rate;
    out->startTime = microseconds(st->start_time, st->time_base);
    out->duration = microseconds(st->duration, st->time_base);
    const AVDictionaryEntry *language = av_dict_get(st->metadata, "language", NULL, 0);
    if (language) snprintf(out->language, sizeof out->language, "%s", language->value);
    const AVDictionaryEntry *title = av_dict_get(st->metadata, "title", NULL, 0);
    if (title) snprintf(out->title, sizeof out->title, "%s", title->value);
    out->isDefault = (st->disposition & AV_DISPOSITION_DEFAULT) != 0;
    out->isForced = (st->disposition & AV_DISPOSITION_FORCED) != 0;
    const AVCodecDescriptor *descriptor = avcodec_descriptor_get(par->codec_id);
    out->isText = descriptor && (descriptor->props & AV_CODEC_PROP_TEXT_SUB);
    out->extradata = par->extradata;
    out->extradataSize = par->extradata_size;
    return 0;
}

int tvm_keyframes(const TVMInput *input, int index, int64_t *times, int capacity) {
    if (index < 0 || index >= (int)input->format->nb_streams) return 0;
    AVStream *st = input->format->streams[index];
    int entries = avformat_index_get_entries_count(st), count = 0;
    int64_t last = INT64_MIN;
    for (int i = 0; i < entries; i++) {
        const AVIndexEntry *entry = avformat_index_get_entry(st, i);
        if (!entry || !(entry->flags & AVINDEX_KEYFRAME) || entry->timestamp == AV_NOPTS_VALUE) continue;
        int64_t time = av_rescale_q(entry->timestamp, st->time_base, AV_TIME_BASE_Q);
        if (time <= last) continue;
        if (count < capacity) times[count] = time;
        count++;
        last = time;
    }
    return count;
}

// MARK: - Cursor

typedef struct Track {
    struct TVMCursor *owner;
    int index;
    TVMTrack spec;
    AVStream *in;
    enum AVMediaType type;
    /// Output clock: 90 kHz for video, the sample rate for audio.
    AVRational outBase;
    int64_t outOffset;
    AVCodecContext *decoder, *encoder;
    SwrContext *resampler;
    AVChannelLayout resamplerLayout;
    int resamplerFormat, resamplerRate;
    AVAudioFifo *fifo;
    struct SwsContext *scaler;
    AVFrame *scaled;
    /// Audio: the next sample's time (output clock, before the offset); AV_NOPTS_VALUE after a reset.
    int64_t nextSample;
    /// Audio conversion just restarted: the encoder's priming before the segment's start is dropped.
    int fresh;
    /// Video conversion: the next frame starts the segment, as a keyframe.
    int firstFrame;
    int64_t lastFramePts;
    /// Decoded video frames at or past the segment's end, for the segment after it.
    AVFrame **held;
    int heldCount, heldCapacity;
    AVFormatContext *mux;
    /// The writer's output passes through a filter of top-level boxes: an initialization segment keeps only
    /// ftyp and moov, a media segment everything else.
    int keepHeader, boxFill, boxPasses;
    uint8_t box[16];
    uint64_t boxLeft;
    /// The muxer needs a packet before its moov (AC-3 and E-AC-3 read their configuration from one): the
    /// track's first packet, kept for its initialization segment.
    int delayed;
    AVPacket *sample;
    int64_t fragmentStart, lastDts;
    /// The packet written last, held back until the next one gives its exact duration (container durations
    /// are often rounded, and the muxer takes a fragment's end from them).
    AVPacket *waiting;
    /// Copied video's decode times, rebuilt from presentation times (Matroska stores only those): the
    /// smallest of the last `reorder` + 1, in a sorted window. Each segment starts it afresh.
    int64_t window[17];
    int windowCount, reorder, decoded;
    int64_t frameDuration;
    int started, ended;
} Track;

struct TVMCursor {
    TVMInput *input;
    Track *tracks;
    int count;
    int *trackOf;
    int videoStream;
    int64_t offset;
    /// Where a segment begins that just goes on reading; INT64_MIN when the reader must seek first.
    int64_t nextStart;
    int untouched, eof;
    AVPacket **pending;
    int pendingHead, pendingCount, pendingCapacity;
    AVPacket *packet, *encoded;
    AVFrame *frame;
    int64_t start, end, readPosition;
    const uint8_t *active;
    void *context;
    TVMWriteFunction write;
    TVMCueFunction cue;
};

static int header_box(const uint8_t *type) { return !memcmp(type, "ftyp", 4) || !memcmp(type, "moov", 4); }

static int sink_write(void *opaque, const uint8_t *bytes, int size) {
    Track *track = opaque;
    TVMCursor *cursor = track->owner;
    int total = size;
    while (size > 0) {
        if (!track->boxLeft) {
            // A box header: its size, its type, and a 64-bit size when the first one says 1.
            int need = track->boxFill >= 8 && track->box[0] == 0 && track->box[1] == 0 && track->box[2] == 0 && track->box[3] == 1 ? 16 : 8;
            int take = FFMIN(need - track->boxFill, size);
            memcpy(track->box + track->boxFill, bytes, take);
            track->boxFill += take; bytes += take; size -= take;
            if (track->boxFill < need) continue;
            if (need == 8 && track->box[0] == 0 && track->box[1] == 0 && track->box[2] == 0 && track->box[3] == 1) continue;
            uint64_t length = need == 16 ? AV_RB64(track->box + 8) : AV_RB32(track->box);
            track->boxPasses = header_box(track->box + 4) == track->keepHeader;
            if (track->boxPasses && cursor->write) cursor->write(cursor->context, track->index, track->box, need);
            track->boxLeft = length == 0 ? UINT64_MAX : (length > (uint64_t)need ? length - need : 0);
            track->boxFill = 0;
            continue;
        }
        int take = (int)FFMIN((uint64_t)size, track->boxLeft);
        if (track->boxPasses && cursor->write) cursor->write(cursor->context, track->index, bytes, take);
        if (track->boxLeft != UINT64_MAX) track->boxLeft -= take;
        bytes += take; size -= take;
    }
    return total;
}

static void free_mux(AVFormatContext **mux) {
    if (!*mux) return;
    if ((*mux)->pb) { av_freep(&(*mux)->pb->buffer); avio_context_free(&(*mux)->pb); }
    avformat_free_context(*mux);
    *mux = NULL;
}

/// A fragmented-MP4 writer for one track. Every segment's writer starts with the same ftyp and moov; only the
/// initialization segment keeps them. frag_discont makes each fragment's decode time the packet's own.
static int open_mux(Track *track, AVCodecContext *encoder, int keepHeader) {
    int delayed = track->delayed && !encoder;
    AVFormatContext *mux = NULL;
    int status = avformat_alloc_output_context2(&mux, NULL, "mp4", NULL);
    if (status < 0) return status;
    AVStream *st = avformat_new_stream(mux, NULL);
    if (!st) { free_mux(&mux); return AVERROR(ENOMEM); }
    status = encoder ? avcodec_parameters_from_context(st->codecpar, encoder) : avcodec_parameters_copy(st->codecpar, track->in->codecpar);
    if (status < 0) { free_mux(&mux); return status; }
    st->codecpar->codec_tag = 0;
    if (st->codecpar->codec_id == AV_CODEC_ID_HEVC)
        st->codecpar->codec_tag = track->spec.dolbyVision == TVMDolbyVisionDVH1 ? MKTAG('d', 'v', 'h', '1') : MKTAG('h', 'v', 'c', '1');
    if (encoder || track->spec.dolbyVision == TVMDolbyVisionDrop)
        av_packet_side_data_remove(st->codecpar->coded_side_data, &st->codecpar->nb_coded_side_data, AV_PKT_DATA_DOVI_CONF);
    st->time_base = track->outBase;
    if (track->type == AVMEDIA_TYPE_AUDIO && !st->codecpar->frame_size) {
        switch (st->codecpar->codec_id) {
        case AV_CODEC_ID_AAC: st->codecpar->frame_size = 1024; break;
        case AV_CODEC_ID_AC3: case AV_CODEC_ID_EAC3: st->codecpar->frame_size = 1536; break;
        case AV_CODEC_ID_MP3: st->codecpar->frame_size = 1152; break;
        default: break;
        }
    }
    if (track->type == AVMEDIA_TYPE_VIDEO) {
        st->avg_frame_rate = track->in->avg_frame_rate;
        if (!st->codecpar->sample_aspect_ratio.num) st->codecpar->sample_aspect_ratio = track->in->sample_aspect_ratio;
    }
    const int bufferSize = 64 << 10;
    uint8_t *buffer = av_malloc(bufferSize);
    mux->pb = buffer ? avio_alloc_context(buffer, bufferSize, 1, track, NULL, sink_write, NULL) : NULL;
    if (!mux->pb) { av_free(buffer); free_mux(&mux); return AVERROR(ENOMEM); }
    // Dolby Vision's dvcC box is "unofficial" to FFmpeg; Apple players read it.
    mux->strict_std_compliance = FF_COMPLIANCE_UNOFFICIAL;
    mux->avoid_negative_ts = AVFMT_AVOID_NEG_TS_DISABLED;
    AVDictionary *options = NULL;
    av_dict_set(&options, "movflags", delayed ? "frag_custom+delay_moov+default_base_moof+frag_discont+skip_trailer"
                                               : "frag_custom+empty_moov+default_base_moof+frag_discont+skip_trailer", 0);
    av_dict_set(&options, "use_editlist", "0", 0);
    track->keepHeader = keepHeader;
    track->boxFill = 0; track->boxLeft = 0; track->boxPasses = 0;
    status = avformat_write_header(mux, &options);
    av_dict_free(&options);
    if (status >= 0) avio_flush(mux->pb);
    if (status < 0) { free_mux(&mux); return status; }
    track->mux = mux;
    track->fragmentStart = track->lastDts = AV_NOPTS_VALUE;
    if (track->waiting) av_packet_unref(track->waiting);
    return 0;
}

static int emit(Track *track) {
    AVPacket *packet = track->waiting;
    if (!packet || !packet->data) return 0;
    if (track->fragmentStart == AV_NOPTS_VALUE) track->fragmentStart = packet->dts;
    else if (av_rescale_q(packet->dts - track->fragmentStart, track->outBase, AV_TIME_BASE_Q) >= FRAGMENT) {
        int status = av_write_frame(track->mux, NULL);
        if (status < 0) { av_packet_unref(packet); return status; }
        avio_flush(track->mux->pb);
        track->fragmentStart = packet->dts;
    }
    int status = av_write_frame(track->mux, packet);
    av_packet_unref(packet);
    return status;
}

static int close_mux(Track *track) {
    if (!track->mux) return 0;
    int status = emit(track);
    if (status >= 0) status = av_write_frame(track->mux, NULL);
    if (status >= 0) status = av_write_trailer(track->mux);
    avio_flush(track->mux->pb);
    free_mux(&track->mux);
    return status < 0 ? status : 0;
}

/// Writes a packet already on the output clock (before the offset), in fragments of about a second.
static int write_out(Track *track, AVPacket *packet) {
    if (!track->mux) return 0;
    if (packet->pts != AV_NOPTS_VALUE) packet->pts += track->outOffset;
    if (packet->dts != AV_NOPTS_VALUE) packet->dts += track->outOffset;
    if (packet->dts == AV_NOPTS_VALUE) packet->dts = packet->pts;
    if (packet->pts == AV_NOPTS_VALUE) packet->pts = packet->dts;
    if (packet->dts == AV_NOPTS_VALUE) return 0;
    if (track->lastDts != AV_NOPTS_VALUE && packet->dts <= track->lastDts) packet->dts = track->lastDts + 1;
    if (packet->pts < packet->dts) packet->pts = packet->dts;
    track->lastDts = packet->dts;
    packet->stream_index = 0;
    if (!track->waiting && !(track->waiting = av_packet_alloc())) return AVERROR(ENOMEM);
    if (track->waiting->data) track->waiting->duration = packet->dts - track->waiting->dts;
    int status = emit(track);
    if (status < 0) return status;
    return av_packet_ref(track->waiting, packet);
}

static int open_decoder(Track *track) {
    const AVCodec *codec = avcodec_find_decoder(track->in->codecpar->codec_id);
    if (!codec) return AVERROR_DECODER_NOT_FOUND;
    AVCodecContext *decoder = avcodec_alloc_context3(codec);
    if (!decoder) return AVERROR(ENOMEM);
    int status = avcodec_parameters_to_context(decoder, track->in->codecpar);
    if (status < 0) { avcodec_free_context(&decoder); return status; }
    decoder->pkt_timebase = track->in->time_base;
    decoder->thread_count = 0;
    decoder->thread_type = FF_THREAD_FRAME | FF_THREAD_SLICE;
    status = avcodec_open2(decoder, codec, NULL);
    if (status < 0) { avcodec_free_context(&decoder); return status; }
    track->decoder = decoder;
    return 0;
}

static int source_depth(const Track *track) {
    const AVPixFmtDescriptor *pixels = av_pix_fmt_desc_get(track->in->codecpar->format);
    return pixels ? pixels->comp[0].depth : 8;
}

static int open_video_encoder(Track *track, AVCodecContext **out) {
    const AVCodecParameters *par = track->in->codecpar;
    int hevc = track->spec.mode == TVMModeHEVC, deep = hevc && source_depth(track) > 8;
    const AVCodec *codec = avcodec_find_encoder_by_name(hevc ? "hevc_videotoolbox" : "h264_videotoolbox");
    if (!codec) return AVERROR_ENCODER_NOT_FOUND;
    AVCodecContext *encoder = avcodec_alloc_context3(codec);
    if (!encoder) return AVERROR(ENOMEM);
    encoder->width = par->width;
    encoder->height = par->height;
    // 8-bit 4:2:0 goes to VideoToolbox as it is; anything else is converted once, on the way in.
    encoder->pix_fmt = deep ? AV_PIX_FMT_P010LE : par->format == AV_PIX_FMT_YUV420P ? AV_PIX_FMT_YUV420P : AV_PIX_FMT_NV12;
    encoder->time_base = track->outBase;
    AVRational rate = track->in->avg_frame_rate.num && track->in->avg_frame_rate.den ? track->in->avg_frame_rate : track->in->r_frame_rate;
    if (rate.num && rate.den) encoder->framerate = rate;
    encoder->gop_size = rate.num && rate.den ? (int)(2 * av_q2d(rate) + 0.5) : 48;
    encoder->max_b_frames = 0;
    encoder->bit_rate = track->spec.bitRate > 0 ? track->spec.bitRate : 6000000;
    encoder->sample_aspect_ratio = par->sample_aspect_ratio.num ? par->sample_aspect_ratio : track->in->sample_aspect_ratio;
    encoder->color_range = par->color_range == AVCOL_RANGE_UNSPECIFIED ? AVCOL_RANGE_MPEG : par->color_range;
    encoder->color_primaries = par->color_primaries;
    encoder->color_trc = par->color_trc;
    encoder->colorspace = par->color_space;
    encoder->flags |= AV_CODEC_FLAG_GLOBAL_HEADER;
    av_opt_set_int(encoder->priv_data, "allow_sw", 1, 0);
    av_opt_set_int(encoder->priv_data, "prio_speed", 1, 0);
    av_opt_set(encoder->priv_data, "profile", hevc ? (deep ? "main10" : "main") : "high", 0);
    int status = avcodec_open2(encoder, codec, NULL);
    if (status < 0) { avcodec_free_context(&encoder); return status; }
    *out = encoder;
    return 0;
}

static int audio_rate(const Track *track) {
    int rate = track->in->codecpar->sample_rate;
    return rate >= 8000 && rate <= 48000 ? rate : 48000;
}

static int open_audio_encoder(Track *track, AVCodecContext **out) {
    const AVCodec *codec = avcodec_find_encoder_by_name("aac_at");
    if (!codec) return AVERROR_ENCODER_NOT_FOUND;
    AVCodecContext *encoder = avcodec_alloc_context3(codec);
    if (!encoder) return AVERROR(ENOMEM);
    encoder->sample_rate = audio_rate(track);
    // AudioToolbox takes 5.1 with side surrounds, not FFmpeg's default 5.1 (back).
    if (track->spec.channels == 6) encoder->ch_layout = (AVChannelLayout)AV_CHANNEL_LAYOUT_5POINT1;
    else av_channel_layout_default(&encoder->ch_layout, track->spec.channels == 1 ? 1 : 2);
    encoder->sample_fmt = AV_SAMPLE_FMT_S16;
    encoder->bit_rate = track->spec.bitRate > 0 ? track->spec.bitRate : 192000;
    encoder->time_base = (AVRational){1, encoder->sample_rate};
    encoder->flags |= AV_CODEC_FLAG_GLOBAL_HEADER;
    int status = avcodec_open2(encoder, codec, NULL);
    if (status < 0) { avcodec_free_context(&encoder); return status; }
    *out = encoder;
    return 0;
}

static void drop_held(Track *track) {
    for (int i = 0; i < track->heldCount; i++) av_frame_free(&track->held[i]);
    track->heldCount = 0;
}

static int hold(Track *track, const AVFrame *frame) {
    if (track->heldCount == track->heldCapacity) {
        int capacity = track->heldCapacity ? track->heldCapacity * 2 : 8;
        AVFrame **held = av_realloc_array(track->held, capacity, sizeof(AVFrame *));
        if (!held) return AVERROR(ENOMEM);
        track->held = held; track->heldCapacity = capacity;
    }
    AVFrame *copy = av_frame_clone(frame);
    if (!copy) return AVERROR(ENOMEM);
    track->held[track->heldCount++] = copy;
    return 0;
}

/// Forgets the reader's state after a seek: codecs restart and nothing carries over.
static void reset_track(Track *track) {
    track->started = track->ended = 0;
    if (track->decoder) avcodec_flush_buffers(track->decoder);
    if (track->type == AVMEDIA_TYPE_AUDIO) avcodec_free_context(&track->encoder);
    swr_free(&track->resampler);
    if (track->fifo) { av_audio_fifo_free(track->fifo); track->fifo = NULL; }
    drop_held(track);
    track->nextSample = AV_NOPTS_VALUE;
    track->fresh = 1;
    track->lastFramePts = AV_NOPTS_VALUE;
}

TVMCursor *tvm_cursor_create(TVMInput *input, const TVMTrack *tracks, int count, int64_t offset) {
    if (count <= 0 || count > 64) return NULL;
    TVMCursor *cursor = av_mallocz(sizeof(TVMCursor));
    if (!cursor) return NULL;
    int streams = (int)input->format->nb_streams;
    cursor->input = input;
    cursor->tracks = av_calloc(count, sizeof(Track));
    cursor->trackOf = av_malloc_array(streams, sizeof(int));
    cursor->packet = av_packet_alloc();
    cursor->encoded = av_packet_alloc();
    cursor->frame = av_frame_alloc();
    if (!cursor->tracks || !cursor->trackOf || !cursor->packet || !cursor->encoded || !cursor->frame) { tvm_cursor_free(cursor); return NULL; }
    cursor->count = count;
    cursor->offset = offset;
    cursor->videoStream = -1;
    cursor->nextStart = INT64_MIN;
    cursor->untouched = 1;
    for (int i = 0; i < streams; i++) cursor->trackOf[i] = -1;
    for (int i = 0; i < count; i++) {
        Track *track = &cursor->tracks[i];
        track->owner = cursor;
        track->index = i;
        track->spec = tracks[i];
        if (tracks[i].stream < 0 || tracks[i].stream >= streams || cursor->trackOf[tracks[i].stream] >= 0) { tvm_cursor_free(cursor); return NULL; }
        track->in = input->format->streams[tracks[i].stream];
        track->type = track->in->codecpar->codec_type;
        cursor->trackOf[tracks[i].stream] = i;
        if (track->type == AVMEDIA_TYPE_VIDEO) {
            cursor->videoStream = tracks[i].stream;
            track->outBase = (AVRational){1, 90000};
        } else if (track->type == AVMEDIA_TYPE_AUDIO) {
            track->outBase = (AVRational){1, track->spec.mode == TVMModeAAC ? audio_rate(track) : (track->in->codecpar->sample_rate > 0 ? track->in->codecpar->sample_rate : 48000)};
        } else track->outBase = AV_TIME_BASE_Q;
        track->outOffset = av_rescale_q(offset, AV_TIME_BASE_Q, track->outBase);
        track->nextSample = track->lastFramePts = AV_NOPTS_VALUE;
        track->fresh = 1;
        const AVCodecParameters *par = track->in->codecpar;
        enum AVCodecID codec = par->codec_id;
        track->delayed = track->spec.mode == TVMModeCopy &&
            (codec == AV_CODEC_ID_AC3 || codec == AV_CODEC_ID_EAC3 || codec == AV_CODEC_ID_TRUEHD ||
             (!par->extradata_size && (codec == AV_CODEC_ID_AAC || codec == AV_CODEC_ID_H264 || codec == AV_CODEC_ID_HEVC)));
    }
    // The demuxer skips what isn't written: other audio languages, cover art, fonts.
    for (int i = 0; i < streams; i++)
        input->format->streams[i]->discard = cursor->trackOf[i] >= 0 ? AVDISCARD_DEFAULT : AVDISCARD_ALL;
    return cursor;
}

static void clear_pending(TVMCursor *cursor) {
    for (int i = 0; i < cursor->pendingCount; i++)
        av_packet_free(&cursor->pending[(cursor->pendingHead + i) % cursor->pendingCapacity]);
    cursor->pendingHead = cursor->pendingCount = 0;
}

void tvm_cursor_free(TVMCursor *cursor) {
    if (!cursor) return;
    if (cursor->pending) clear_pending(cursor);
    av_free(cursor->pending);
    for (int i = 0; cursor->tracks && i < cursor->count; i++) {
        Track *track = &cursor->tracks[i];
        free_mux(&track->mux);
        avcodec_free_context(&track->decoder);
        avcodec_free_context(&track->encoder);
        swr_free(&track->resampler);
        av_channel_layout_uninit(&track->resamplerLayout);
        if (track->fifo) av_audio_fifo_free(track->fifo);
        sws_freeContext(track->scaler);
        av_frame_free(&track->scaled);
        drop_held(track);
        av_free(track->held);
        av_packet_free(&track->sample);
        av_packet_free(&track->waiting);
    }
    av_free(cursor->tracks);
    av_free(cursor->trackOf);
    av_packet_free(&cursor->packet);
    av_packet_free(&cursor->encoded);
    av_frame_free(&cursor->frame);
    av_free(cursor);
}

/// Moves the packet's data to the end of the queue the next segment reads first.
static int push_pending(TVMCursor *cursor, AVPacket *packet) {
    if (cursor->pendingCount == cursor->pendingCapacity) {
        int capacity = cursor->pendingCapacity ? cursor->pendingCapacity * 2 : 64;
        AVPacket **queue = av_malloc_array(capacity, sizeof(AVPacket *));
        if (!queue) return AVERROR(ENOMEM);
        for (int i = 0; i < cursor->pendingCount; i++)
            queue[i] = cursor->pending[(cursor->pendingHead + i) % cursor->pendingCapacity];
        av_free(cursor->pending);
        cursor->pending = queue; cursor->pendingCapacity = capacity; cursor->pendingHead = 0;
    }
    AVPacket *copy = av_packet_alloc();
    if (!copy) return AVERROR(ENOMEM);
    av_packet_move_ref(copy, packet);
    cursor->pending[(cursor->pendingHead + cursor->pendingCount) % cursor->pendingCapacity] = copy;
    cursor->pendingCount++;
    return 0;
}

static AVPacket *pop_pending(TVMCursor *cursor) {
    if (!cursor->pendingCount) return NULL;
    AVPacket *packet = cursor->pending[cursor->pendingHead];
    cursor->pendingHead = (cursor->pendingHead + 1) % cursor->pendingCapacity;
    cursor->pendingCount--;
    return packet;
}

// MARK: Audio

static int encode_audio(TVMCursor *cursor, Track *track, AVFrame *frame) {
    int status = avcodec_send_frame(track->encoder, frame);
    if (status < 0 && status != AVERROR_EOF) return status;
    while ((status = avcodec_receive_packet(track->encoder, cursor->encoded)) >= 0) {
        AVPacket *packet = cursor->encoded;
        // The encoder times its packets back by its delay (FFmpeg's frame queue), so a restarted one begins
        // with priming before the segment's start, which was played already.
        if (track->fresh && packet->pts != AV_NOPTS_VALUE &&
            av_rescale_q(packet->pts + packet->duration, track->outBase, AV_TIME_BASE_Q) <= cursor->start) {
            av_packet_unref(packet);
            continue;
        }
        track->fresh = 0;
        status = write_out(track, packet);
        av_packet_unref(packet);
        if (status < 0) return status;
    }
    return status == AVERROR(EAGAIN) || status == AVERROR_EOF ? 0 : status;
}

static int drain_audio(TVMCursor *cursor, Track *track, int final) {
    AVCodecContext *encoder = track->encoder;
    if (!encoder || !track->fifo) return 0;
    while (av_audio_fifo_size(track->fifo) >= encoder->frame_size || (final && av_audio_fifo_size(track->fifo) > 0)) {
        AVFrame *frame = av_frame_alloc();
        if (!frame) return AVERROR(ENOMEM);
        frame->nb_samples = encoder->frame_size;
        frame->format = encoder->sample_fmt;
        frame->sample_rate = encoder->sample_rate;
        av_channel_layout_copy(&frame->ch_layout, &encoder->ch_layout);
        int status = av_frame_get_buffer(frame, 0);
        if (status < 0) { av_frame_free(&frame); return status; }
        int got = av_audio_fifo_read(track->fifo, (void **)frame->data, encoder->frame_size);
        if (got < encoder->frame_size)
            av_samples_set_silence(frame->data, got, encoder->frame_size - got, encoder->ch_layout.nb_channels, encoder->sample_fmt);
        frame->pts = track->nextSample;
        track->nextSample += encoder->frame_size;
        status = encode_audio(cursor, track, frame);
        av_frame_free(&frame);
        if (status < 0) return status;
    }
    return final ? encode_audio(cursor, track, NULL) : 0;
}

static int feed_audio(TVMCursor *cursor, Track *track, AVFrame *frame) {
    int status;
    if (!track->encoder && (status = open_audio_encoder(track, &track->encoder)) < 0) return status;
    AVCodecContext *encoder = track->encoder;
    if (track->resampler && (frame->format != track->resamplerFormat || frame->sample_rate != track->resamplerRate ||
                             av_channel_layout_compare(&frame->ch_layout, &track->resamplerLayout)))
        swr_free(&track->resampler);
    if (!track->resampler) {
        // More than two channels become 5.1 (DTS and TrueHD 7.1 fold their back channels in); fewer stay.
        status = swr_alloc_set_opts2(&track->resampler, &encoder->ch_layout, encoder->sample_fmt, encoder->sample_rate,
                                     &frame->ch_layout, frame->format, frame->sample_rate, 0, NULL);
        if (status < 0 || (status = swr_init(track->resampler)) < 0) { swr_free(&track->resampler); return status; }
        track->resamplerFormat = frame->format;
        track->resamplerRate = frame->sample_rate;
        av_channel_layout_uninit(&track->resamplerLayout);
        av_channel_layout_copy(&track->resamplerLayout, &frame->ch_layout);
    }
    if (!track->fifo && !(track->fifo = av_audio_fifo_alloc(encoder->sample_fmt, encoder->ch_layout.nb_channels, encoder->frame_size * 4)))
        return AVERROR(ENOMEM);
    if (frame->best_effort_timestamp != AV_NOPTS_VALUE) {
        int64_t at = av_rescale_q(frame->best_effort_timestamp, track->in->time_base, track->outBase);
        int64_t expected = track->nextSample == AV_NOPTS_VALUE ? AV_NOPTS_VALUE : track->nextSample + av_audio_fifo_size(track->fifo);
        // The first frame, or a jump in the file's clock: samples count on from here.
        if (expected == AV_NOPTS_VALUE || llabs(at - expected) > encoder->sample_rate / 5) {
            av_audio_fifo_reset(track->fifo);
            track->nextSample = at;
        }
    } else if (track->nextSample == AV_NOPTS_VALUE) return 0;
    int capacity = swr_get_out_samples(track->resampler, frame->nb_samples);
    if (capacity <= 0) return 0;
    uint8_t **samples = NULL;
    status = av_samples_alloc_array_and_samples(&samples, NULL, encoder->ch_layout.nb_channels, capacity, encoder->sample_fmt, 0);
    if (status < 0) return status;
    int converted = swr_convert(track->resampler, samples, capacity, (const uint8_t **)frame->extended_data, frame->nb_samples);
    if (converted > 0) av_audio_fifo_write(track->fifo, (void **)samples, converted);
    av_freep(&samples[0]);
    av_freep(&samples);
    if (converted < 0) return converted;
    return drain_audio(cursor, track, 0);
}

static int convert_audio(TVMCursor *cursor, Track *track, AVPacket *packet) {
    int status;
    if (!track->decoder && (status = open_decoder(track)) < 0) return status;
    status = avcodec_send_packet(track->decoder, packet);
    // A damaged packet is skipped, like a player would.
    if (status < 0 && status != AVERROR(EAGAIN) && status != AVERROR_EOF) return 0;
    while ((status = avcodec_receive_frame(track->decoder, cursor->frame)) >= 0) {
        status = feed_audio(cursor, track, cursor->frame);
        av_frame_unref(cursor->frame);
        if (status < 0) return status;
    }
    if (!packet) return drain_audio(cursor, track, 1);
    return status == AVERROR(EAGAIN) || status == AVERROR_EOF ? 0 : status;
}

/// Copied audio is retimed by its sample count: Matroska's millisecond clock would otherwise make every
/// frame's duration jitter.
static int copy_audio(Track *track, AVPacket *packet) {
    av_packet_rescale_ts(packet, track->in->time_base, track->outBase);
    int64_t samples = packet->duration > 0 ? packet->duration : av_get_audio_frame_duration2(track->in->codecpar, packet->size);
    if (packet->pts == AV_NOPTS_VALUE) packet->pts = packet->dts;
    if (track->nextSample != AV_NOPTS_VALUE &&
        (packet->pts == AV_NOPTS_VALUE || llabs(packet->pts - track->nextSample) <= track->outBase.den / 50))
        packet->pts = track->nextSample;
    if (packet->pts == AV_NOPTS_VALUE) return 0;
    packet->dts = packet->pts;
    if (samples > 0) packet->duration = samples;
    track->nextSample = packet->pts + (samples > 0 ? samples : 0);
    return write_out(track, packet);
}

// MARK: Video

static int receive_video(TVMCursor *cursor, Track *track) {
    int status;
    while ((status = avcodec_receive_packet(track->encoder, cursor->encoded)) >= 0) {
        status = write_out(track, cursor->encoded);
        av_packet_unref(cursor->encoded);
        if (status < 0) return status;
    }
    return status == AVERROR(EAGAIN) || status == AVERROR_EOF ? 0 : status;
}

static int encode_video(TVMCursor *cursor, Track *track, AVFrame *frame) {
    int status;
    if (!track->encoder) {
        if ((status = open_video_encoder(track, &track->encoder)) < 0) return status;
        track->firstFrame = 1;
        track->lastFramePts = AV_NOPTS_VALUE;
    }
    AVCodecContext *encoder = track->encoder;
    AVFrame *input = frame;
    if (frame->format != encoder->pix_fmt || frame->width != encoder->width || frame->height != encoder->height) {
        track->scaler = sws_getCachedContext(track->scaler, frame->width, frame->height, frame->format,
                                             encoder->width, encoder->height, encoder->pix_fmt, SWS_BILINEAR, NULL, NULL, NULL);
        if (!track->scaler) return AVERROR(EINVAL);
        if (!track->scaled) {
            track->scaled = av_frame_alloc();
            if (!track->scaled) return AVERROR(ENOMEM);
            track->scaled->format = encoder->pix_fmt;
            track->scaled->width = encoder->width;
            track->scaled->height = encoder->height;
            if ((status = av_frame_get_buffer(track->scaled, 0)) < 0) return status;
        }
        if ((status = av_frame_make_writable(track->scaled)) < 0) return status;
        sws_scale(track->scaler, (const uint8_t *const *)frame->data, frame->linesize, 0, frame->height,
                  track->scaled->data, track->scaled->linesize);
        av_frame_copy_props(track->scaled, frame);
        input = track->scaled;
    }
    int64_t pts = av_rescale_q(frame->best_effort_timestamp, track->in->time_base, encoder->time_base);
    if (track->lastFramePts != AV_NOPTS_VALUE && pts <= track->lastFramePts) pts = track->lastFramePts + 1;
    track->lastFramePts = pts;
    input->pts = pts;
    input->duration = frame->duration > 0 ? av_rescale_q(frame->duration, track->in->time_base, encoder->time_base) : 0;
    // Every segment opens with a keyframe of its own.
    input->pict_type = track->firstFrame ? AV_PICTURE_TYPE_I : AV_PICTURE_TYPE_NONE;
    track->firstFrame = 0;
    if ((status = avcodec_send_frame(encoder, input)) < 0) return status;
    return receive_video(cursor, track);
}

static int take_frame(TVMCursor *cursor, Track *track, AVFrame *frame) {
    if (frame->best_effort_timestamp == AV_NOPTS_VALUE) return 0;
    int64_t time = av_rescale_q(frame->best_effort_timestamp, track->in->time_base, AV_TIME_BASE_Q);
    if (time < cursor->start - TOLERANCE) return 0;
    if (cursor->end >= 0 && time >= cursor->end - TOLERANCE) {
        track->ended = 1;
        return hold(track, frame);
    }
    return encode_video(cursor, track, frame);
}

static int convert_video(TVMCursor *cursor, Track *track, AVPacket *packet) {
    int status;
    if (!track->decoder && (status = open_decoder(track)) < 0) return status;
    status = avcodec_send_packet(track->decoder, packet);
    if (status < 0 && status != AVERROR(EAGAIN) && status != AVERROR_EOF) return 0;
    while ((status = avcodec_receive_frame(track->decoder, cursor->frame)) >= 0) {
        status = take_frame(cursor, track, cursor->frame);
        av_frame_unref(cursor->frame);
        if (status < 0) return status;
    }
    return status == AVERROR(EAGAIN) || status == AVERROR_EOF ? 0 : status;
}

static int finish_video(TVMCursor *cursor, Track *track) {
    if (!track->encoder) return 0;
    int status = avcodec_send_frame(track->encoder, NULL);
    if (status >= 0) status = receive_video(cursor, track);
    avcodec_free_context(&track->encoder);
    return status;
}

// MARK: Segments

/// The decode time of the next copied video packet in decode order: packet i decodes at the (i - reorder)-th
/// smallest presentation time, which no later packet can undercut; the first ones count back from the segment's
/// keyframe one frame at a time. Never earlier than the previous packet's.
static int64_t decode_time(Track *track, int64_t pts) {
    int count = track->windowCount, at = count;
    while (at > 0 && track->window[at - 1] > pts) { track->window[at] = track->window[at - 1]; at--; }
    track->window[at] = pts;
    track->windowCount = ++count;
    int64_t dts;
    if (count > track->reorder) {
        dts = track->window[0];
        memmove(track->window, track->window + 1, (count - 1) * sizeof(int64_t));
        track->windowCount--;
    } else dts = track->window[0] - (int64_t)(track->reorder - track->decoded) * track->frameDuration;
    track->decoded++;
    if (track->lastDts != AV_NOPTS_VALUE && dts + track->outOffset <= track->lastDts) dts = track->lastDts - track->outOffset + 1;
    return dts;
}

static int64_t packet_time(const Track *track, const AVPacket *packet) {
    int64_t value = packet->pts != AV_NOPTS_VALUE ? packet->pts : packet->dts;
    return value == AV_NOPTS_VALUE ? AV_NOPTS_VALUE : av_rescale_q(value, track->in->time_base, AV_TIME_BASE_Q);
}

/// Sends a packet where it belongs: this segment's output, the queue for the next one, or nowhere.
/// The packet is left empty either way.
static int route(TVMCursor *cursor, AVPacket *packet) {
    int index = packet->stream_index < (int)cursor->input->format->nb_streams ? cursor->trackOf[packet->stream_index] : -1;
    if (index < 0) { av_packet_unref(packet); return 0; }
    Track *track = &cursor->tracks[index];
    int64_t time = packet_time(track, packet);
    if (time != AV_NOPTS_VALUE && time > cursor->readPosition) cursor->readPosition = time;
    int past = cursor->end >= 0 && time != AV_NOPTS_VALUE && time >= cursor->end;
    int status = 0;
    if (!cursor->active[index] || track->type == AVMEDIA_TYPE_SUBTITLE) {
        if (past) return push_pending(cursor, packet);
        if (cursor->active[index] && time != AV_NOPTS_VALUE && time >= cursor->start - TOLERANCE && cursor->cue) {
            int64_t length = packet->duration > 0 ? av_rescale_q(packet->duration, track->in->time_base, AV_TIME_BASE_Q) : -1;
            cursor->cue(cursor->context, index, time, length >= 0 ? time + length : -1, packet->data, packet->size);
        }
        // An inactive converted video track restarts at a keyframe when it is wanted again.
        if (!cursor->active[index]) track->started = 0;
        av_packet_unref(packet);
        return 0;
    }
    if (track->ended) return push_pending(cursor, packet);
    if (track->type == AVMEDIA_TYPE_VIDEO) {
        int key = (packet->flags & AV_PKT_FLAG_KEY) != 0;
        if (track->spec.mode == TVMModeCopy) {
            if (!track->started) {
                if (!key || time == AV_NOPTS_VALUE || time < cursor->start - TOLERANCE) { av_packet_unref(packet); return 0; }
                if (cursor->end >= 0 && time >= cursor->end - TOLERANCE) {
                    // No keyframe in the whole segment (a long GOP in a file without an index): it shows the
                    // next one, which also begins the next segment, rather than coming out empty.
                    track->ended = 1;
                    AVPacket *frame = av_packet_clone(packet);
                    if (!frame) { av_packet_unref(packet); return AVERROR(ENOMEM); }
                    av_packet_rescale_ts(frame, track->in->time_base, track->outBase);
                    if (frame->pts != AV_NOPTS_VALUE) frame->dts = decode_time(track, frame->pts);
                    status = write_out(track, frame);
                    av_packet_free(&frame);
                    if (status < 0) { av_packet_unref(packet); return status; }
                    return push_pending(cursor, packet);
                }
                track->started = 1;
            } else if (key && cursor->end >= 0 && time != AV_NOPTS_VALUE && time >= cursor->end - TOLERANCE) {
                track->ended = 1;
                return push_pending(cursor, packet);
            }
            av_packet_rescale_ts(packet, track->in->time_base, track->outBase);
            if (packet->pts != AV_NOPTS_VALUE) packet->dts = decode_time(track, packet->pts);
            status = write_out(track, packet);
        } else {
            if (!track->started) {
                if (!key) { av_packet_unref(packet); return 0; }
                if (track->decoder) avcodec_flush_buffers(track->decoder);
                track->started = 1;
            }
            status = convert_video(cursor, track, packet);
        }
    } else if (track->type == AVMEDIA_TYPE_AUDIO) {
        if (past) { track->ended = 1; return push_pending(cursor, packet); }
        if (time != AV_NOPTS_VALUE && time < cursor->start) { av_packet_unref(packet); return 0; }
        track->started = 1;
        status = track->spec.mode == TVMModeCopy ? copy_audio(track, packet) : convert_audio(cursor, track, packet);
    }
    av_packet_unref(packet);
    return status;
}

/// Whether every active track has reached the segment's end. Subtitles have no packet at each boundary:
/// theirs is reached once the reader is past it.
static int finished(TVMCursor *cursor) {
    if (cursor->end < 0) return 0;
    int reached = cursor->readPosition != INT64_MIN && cursor->readPosition >= cursor->end;
    for (int i = 0; i < cursor->count; i++) {
        Track *track = &cursor->tracks[i];
        if (!cursor->active[i] || track->ended) continue;
        if (track->type == AVMEDIA_TYPE_SUBTITLE) { if (!reached) return 0; continue; }
        // A track can pause (an audio gap, or audio that stops early): don't read on forever for it.
        // Copied video that has begun must reach its next keyframe, or the next segment would lose the frames between.
        int64_t wait = track->type == AVMEDIA_TYPE_VIDEO && track->spec.mode == TVMModeCopy && track->started ? MAXGOP : LOOKAHEAD;
        if (cursor->readPosition != INT64_MIN && cursor->readPosition >= cursor->end + wait) continue;
        return 0;
    }
    return 1;
}

static int64_t indexed_until(AVStream *st) {
    int count = avformat_index_get_entries_count(st);
    const AVIndexEntry *entry = count > 0 ? avformat_index_get_entry(st, count - 1) : NULL;
    return entry ? av_rescale_q(entry->timestamp, st->time_base, AV_TIME_BASE_Q) : INT64_MIN;
}

/// Without an index that reaches the time, FFmpeg would read every packet up to it (a whole download for a
/// remote FLV). A byte position from the average bit rate, corrected until the reader lands a little before
/// the time, costs a few short reads. MPEG streams search by timestamp on their own.
static int seek_by_bytes(TVMCursor *cursor, int64_t start) {
    AVFormatContext *format = cursor->input->format;
    int64_t size = cursor->input->size, duration = format->duration;
    const char *name = format->iformat->name;
    if (size <= 0 || duration <= 0 || !strcmp(name, "mpegts") || !strcmp(name, "mpeg")) return AVERROR(ENOSYS);
    if (cursor->videoStream < 0 || start <= indexed_until(format->streams[cursor->videoStream]) + UNINDEXED) return AVERROR(ENOSYS);
    int64_t first = format->start_time == AV_NOPTS_VALUE ? 0 : format->start_time;
    int64_t target = start - 15000000;
    for (int attempt = 0; attempt < 6; attempt++) {
        int64_t position = av_rescale(FFMAX(target - first, 0), size, duration);
        int status = av_seek_frame(format, -1, FFMIN(position, size - 1), AVSEEK_FLAG_BYTE);
        if (status < 0) return status;
        int64_t time = AV_NOPTS_VALUE;
        for (int read = 0; read < 2000 && time == AV_NOPTS_VALUE; read++) {
            if ((status = av_read_frame(format, cursor->packet)) < 0) return status;
            int index = cursor->packet->stream_index < (int)format->nb_streams ? cursor->trackOf[cursor->packet->stream_index] : -1;
            if (index >= 0) time = packet_time(&cursor->tracks[index], cursor->packet);
            if (time == AV_NOPTS_VALUE) av_packet_unref(cursor->packet);
        }
        if (time == AV_NOPTS_VALUE) return AVERROR_INVALIDDATA;
        // Landed after the time, or far before it: move by the miss, and a margin when too late.
        if ((time > start || time < start - 60000000) && position > 0 && attempt < 5) {
            av_packet_unref(cursor->packet);
            target -= time > start ? time - start + 15000000 : time - (start - 15000000);
            continue;
        }
        return push_pending(cursor, cursor->packet);
    }
    return AVERROR(ENOSYS);
}

static int reposition(TVMCursor *cursor, int64_t start) {
    clear_pending(cursor);
    for (int i = 0; i < cursor->count; i++) reset_track(&cursor->tracks[i]);
    cursor->eof = 0;
    AVFormatContext *format = cursor->input->format;
    // The first segment starts where the reader already is: nothing to seek.
    int64_t first = format->start_time == AV_NOPTS_VALUE ? 0 : format->start_time;
    if (cursor->untouched && start <= first + 500000) return 0;
    int status = seek_by_bytes(cursor, start);
    if (status >= 0) return status;
    clear_pending(cursor);
    if (cursor->videoStream >= 0) {
        AVStream *st = format->streams[cursor->videoStream];
        status = av_seek_frame(format, cursor->videoStream, av_rescale_q(start + TOLERANCE, AV_TIME_BASE_Q, st->time_base), AVSEEK_FLAG_BACKWARD);
    } else status = av_seek_frame(format, -1, start + TOLERANCE, AVSEEK_FLAG_BACKWARD);
    if (status < 0) status = avformat_seek_file(format, -1, INT64_MIN, start, start, 0);
    if (status < 0 && start <= first + 500000) status = avformat_seek_file(format, -1, INT64_MIN, INT64_MIN, INT64_MAX, AVSEEK_FLAG_BYTE);
    return status;
}

/// Reads from the start to the track's first packet. The reader is left there, so the next segment seeks.
static int load_sample(TVMCursor *cursor, Track *track) {
    if (track->sample) return 0;
    AVFormatContext *format = cursor->input->format;
    clear_pending(cursor);
    cursor->nextStart = INT64_MIN;
    cursor->untouched = 0;
    int status = avformat_seek_file(format, -1, INT64_MIN, format->start_time == AV_NOPTS_VALUE ? 0 : format->start_time, INT64_MAX, 0);
    if (status < 0) status = av_seek_frame(format, -1, 0, AVSEEK_FLAG_BYTE);
    if (status < 0) return status;
    for (int read = 0; read < 10000; read++) {
        if ((status = av_read_frame(format, cursor->packet)) < 0) return status;
        if (cursor->packet->stream_index == track->in->index && cursor->packet->size > 0) {
            track->sample = av_packet_alloc();
            if (!track->sample) { av_packet_unref(cursor->packet); return AVERROR(ENOMEM); }
            av_packet_move_ref(track->sample, cursor->packet);
            return 0;
        }
        av_packet_unref(cursor->packet);
    }
    return AVERROR_STREAM_NOT_FOUND;
}

int tvm_cursor_init(TVMCursor *cursor, int index, void *context, TVMWriteFunction write, char *error, int errorSize) {
    if (index < 0 || index >= cursor->count) return fail(error, errorSize, AVERROR(EINVAL), "init");
    Track *track = &cursor->tracks[index];
    if (track->type != AVMEDIA_TYPE_VIDEO && track->type != AVMEDIA_TYPE_AUDIO) return fail(error, errorSize, AVERROR(EINVAL), "init");
    AVCodecContext *encoder = NULL;
    int status = 0;
    if (track->spec.mode == TVMModeAAC) status = open_audio_encoder(track, &encoder);
    else if (track->spec.mode == TVMModeH264 || track->spec.mode == TVMModeHEVC) status = open_video_encoder(track, &encoder);
    if (status < 0) return fail(error, errorSize, status, "encoder");
    if (track->delayed && !encoder && (status = load_sample(cursor, track)) < 0) return fail(error, errorSize, status, "first packet");
    cursor->context = context;
    cursor->write = write;
    AVFormatContext *saved = track->mux;
    int64_t fragmentStart = track->fragmentStart, lastDts = track->lastDts, nextSample = track->nextSample;
    track->mux = NULL;
    status = open_mux(track, encoder, 1);
    if (status >= 0 && track->delayed && !encoder) {
        // The moov comes out with the first fragment; the box filter keeps it and drops the fragment.
        AVPacket *packet = av_packet_clone(track->sample);
        if (!packet) status = AVERROR(ENOMEM);
        else {
            av_packet_rescale_ts(packet, track->in->time_base, track->outBase);
            if (packet->dts == AV_NOPTS_VALUE) packet->dts = packet->pts;
            status = write_out(track, packet);
            av_packet_free(&packet);
        }
        if (status >= 0) status = close_mux(track);
    }
    if (track->mux) { avio_flush(track->mux->pb); free_mux(&track->mux); }
    track->mux = saved;
    track->fragmentStart = fragmentStart; track->lastDts = lastDts; track->nextSample = nextSample;
    avcodec_free_context(&encoder);
    cursor->write = NULL;
    return status < 0 ? fail(error, errorSize, status, "header") : 0;
}

int tvm_cursor_segment(TVMCursor *cursor, int64_t start, int64_t end, const uint8_t *active, void *context,
                       TVMWriteFunction write, TVMCueFunction cue, char *error, int errorSize) {
    cursor->context = context; cursor->write = write; cursor->cue = cue; cursor->active = active;
    cursor->start = start; cursor->end = end;
    cursor->readPosition = INT64_MIN;
    int status = 0;
    if (cursor->nextStart == INT64_MIN || start != cursor->nextStart) {
        if ((status = reposition(cursor, start)) < 0) { fail(error, errorSize, status, "seek"); goto done; }
    } else {
        // Going on from the previous segment: its packets and frames past the end begin this one.
        for (int i = 0; i < cursor->count; i++) {
            Track *track = &cursor->tracks[i];
            track->ended = 0;
            if (track->type == AVMEDIA_TYPE_VIDEO && track->spec.mode == TVMModeCopy) track->started = 0;
        }
    }
    cursor->untouched = 0;
    for (int i = 0; i < cursor->count; i++) {
        Track *track = &cursor->tracks[i];
        if (!active[i] || (track->type != AVMEDIA_TYPE_VIDEO && track->type != AVMEDIA_TYPE_AUDIO)) continue;
        // A converted track's writer takes its parameters from the encoder: audio keeps one across
        // segments (its priming would otherwise gap every segment), video opens one per segment.
        if (track->spec.mode == TVMModeAAC && !track->encoder) status = open_audio_encoder(track, &track->encoder);
        else if (track->type == AVMEDIA_TYPE_VIDEO && track->spec.mode != TVMModeCopy) {
            avcodec_free_context(&track->encoder);
            status = open_video_encoder(track, &track->encoder);
            track->firstFrame = 1;
            track->lastFramePts = AV_NOPTS_VALUE;
        }
        if (status >= 0) status = open_mux(track, track->spec.mode == TVMModeCopy ? NULL : track->encoder, 0);
        if (status < 0) { fail(error, errorSize, status, "writer"); goto done; }
        if (track->type == AVMEDIA_TYPE_VIDEO && track->spec.mode == TVMModeCopy) {
            // One frame more than the stream says it reorders: a later decode time costs nothing.
            track->reorder = FFMIN(16, FFMAX(track->in->codecpar->video_delay, 0) + 1);
            AVRational rate = track->in->avg_frame_rate.num && track->in->avg_frame_rate.den ? track->in->avg_frame_rate : track->in->r_frame_rate;
            track->frameDuration = rate.num && rate.den ? av_rescale_q(1, av_inv_q(rate), track->outBase) : track->outBase.den / 24;
            track->windowCount = track->decoded = 0;
        }
    }
    // Converted frames decoded past the previous segment's end begin this one.
    for (int i = 0; i < cursor->count; i++) {
        Track *track = &cursor->tracks[i];
        if (!active[i] || track->type != AVMEDIA_TYPE_VIDEO || track->spec.mode == TVMModeCopy || !track->heldCount) continue;
        int count = track->heldCount;
        AVFrame **frames = av_malloc_array(count, sizeof(AVFrame *));
        if (!frames) { status = fail(error, errorSize, AVERROR(ENOMEM), "video"); goto done; }
        memcpy(frames, track->held, count * sizeof(AVFrame *));
        track->heldCount = 0;
        for (int j = 0; j < count; j++) {
            if (status >= 0) status = take_frame(cursor, track, frames[j]);
            av_frame_free(&frames[j]);
        }
        av_free(frames);
        if (status < 0) { fail(error, errorSize, status, "video"); goto done; }
    }
    // Only what the previous segment queued is replayed; what this one queues is for the next.
    int replay = cursor->pendingCount;
    while (!finished(cursor)) {
        AVPacket *queued = replay > 0 ? (replay--, pop_pending(cursor)) : NULL;
        if (!queued) {
            if (cursor->eof) break;
            status = av_read_frame(cursor->input->format, cursor->packet);
            if (status == AVERROR_EOF) { cursor->eof = 1; status = 0; break; }
            if (status < 0) { fail(error, errorSize, status, "read"); goto done; }
        }
        status = route(cursor, queued ? queued : cursor->packet);
        av_packet_free(&queued);
        if (status < 0) { fail(error, errorSize, status, "write"); goto done; }
    }
    if (cursor->eof && !cursor->pendingCount) {
        // The end of the file: what the converters still hold belongs to this, the last segment.
        for (int i = 0; i < cursor->count; i++) {
            Track *track = &cursor->tracks[i];
            if (!active[i] || track->spec.mode == TVMModeCopy || !track->decoder) continue;
            status = track->type == AVMEDIA_TYPE_VIDEO ? convert_video(cursor, track, NULL) : convert_audio(cursor, track, NULL);
            if (status < 0) { fail(error, errorSize, status, "flush"); goto done; }
        }
    }
    for (int i = 0; i < cursor->count; i++) {
        Track *track = &cursor->tracks[i];
        if (!active[i] || track->type != AVMEDIA_TYPE_VIDEO || track->spec.mode == TVMModeCopy) continue;
        if ((status = finish_video(cursor, track)) < 0) { fail(error, errorSize, status, "encode"); goto done; }
    }
    for (int i = 0; i < cursor->count; i++) {
        if ((status = close_mux(&cursor->tracks[i])) < 0) { fail(error, errorSize, status, "finish"); goto done; }
    }
    cursor->nextStart = end >= 0 && !(cursor->eof && !cursor->pendingCount) ? end : INT64_MIN;
    cursor->write = NULL; cursor->cue = NULL; cursor->context = NULL;
    return 0;
done:
    for (int i = 0; i < cursor->count; i++) {
        Track *track = &cursor->tracks[i];
        free_mux(&track->mux);
        if (track->type == AVMEDIA_TYPE_VIDEO) avcodec_free_context(&track->encoder);
    }
    cursor->nextStart = INT64_MIN;
    cursor->write = NULL; cursor->cue = NULL; cursor->context = NULL;
    return status < 0 ? status : AVERROR_UNKNOWN;
}
