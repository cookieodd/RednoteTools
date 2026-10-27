/**
 * RednoteTools 9.52
 */

#import "Tweak.h"

static const NSInteger kRNTBarTag = 77770;
static const NSInteger kRNTOneTag = 77771;
static const NSInteger kRNTAllTag = 77772;
static const NSInteger kRNTToastTag = 77780;
static const NSInteger kRNTHudTag = 77790;
static const NSInteger kRNTHudTitleTag = 77791;
static const NSInteger kRNTHudSubTag = 77792;
static const NSInteger kRNTHudTrackTag = 77793;
static const NSInteger kRNTHudFillTag = 77794;
static const NSInteger kRNTHudPctTag = 77795;
static const CGFloat kRNTBtnH = 32.0;
static const CGFloat kRNTBtnW = 76.0;
static const CGFloat kRNTGap = 8.0;
static const CGFloat kRNTBarBottom = 24.0;

typedef NS_ENUM(NSInteger, RNTHudKind) {
    RNTHudKindNone = 0,
    RNTHudKindSingle = 1,
    RNTHudKindBatch = 2,
};

static NSMutableDictionary *livePhotoUrlCache;
static NSMutableDictionary *commentLivePhotoCache;
static NSMutableDictionary *imageUrlCache;
static NSString *gLastNoteId;
static long long gPendingSaveIndex;
static BOOL gInterceptingNativeSave;
static RNTHudKind gHudKind;
static NSInteger gHudGen;

#pragma mark - Values

static id RNTKVC(id obj, NSString *key) {
    if (!obj || !key.length) return nil;
    @try { return [obj valueForKey:key]; } @catch (NSException *e) { return nil; }
}

static NSString *RNTURLString(id obj) {
    if ([obj isKindOfClass:[NSURL class]]) return [(NSURL *)obj absoluteString];
    if ([obj isKindOfClass:[NSString class]]) return (NSString *)obj;
    return nil;
}

static NSString *RNTPlainURL(id obj) {
    NSString *s = RNTURLString(obj);
    if (!s.length) return nil;
    s = [s stringByReplacingOccurrencesOfString:@"format/heif" withString:@"format/jpg"];
    s = [s stringByReplacingOccurrencesOfString:@"format/webp" withString:@"format/jpg"];
    return s;
}

static NSString *RNTBestImageURL(id obj) {
    NSString *s = RNTPlainURL(obj);
    if (!s.length) return nil;
    static NSRegularExpression *re;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        re = [NSRegularExpression regularExpressionWithPattern:@"/w/\\d+" options:0 error:nil];
    });
    if (re) s = [re stringByReplacingMatchesInString:s options:0 range:NSMakeRange(0, s.length) withTemplate:@"/w/1440"];
    return s;
}

static NSString *RNTStreamURL(id jsonObj) {
    NSDictionary *dict = nil;
    if ([jsonObj isKindOfClass:[NSDictionary class]]) dict = jsonObj;
    else if ([jsonObj isKindOfClass:[NSString class]]) {
        NSData *data = [(NSString *)jsonObj dataUsingEncoding:NSUTF8StringEncoding];
        id parsed = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        if ([parsed isKindOfClass:[NSDictionary class]]) dict = parsed;
    }
    if (!dict) return nil;
    NSDictionary *stream = dict[@"stream"];
    if (![stream isKindOfClass:[NSDictionary class]] && [dict[@"media"] isKindOfClass:[NSDictionary class]]) {
        stream = dict[@"media"][@"stream"];
    }
    if (![stream isKindOfClass:[NSDictionary class]]) return nil;
    for (NSString *codec in @[@"h265", @"h264"]) {
        NSArray *arr = stream[codec];
        if (![arr isKindOfClass:[NSArray class]] || !arr.count) continue;
        id first = arr.firstObject;
        if (![first isKindOfClass:[NSDictionary class]]) continue;
        NSString *u = first[@"master_url"] ?: first[@"url"];
        if (u.length) return u;
    }
    return nil;
}

#pragma mark - URL cache

static NSString *RNTCacheKey(NSString *noteId, long long index) {
    if (!noteId.length) return nil;
    return [NSString stringWithFormat:@"%@_%lld", noteId, index];
}

static void RNTCacheEvictNote(NSString *noteId) {
    if (!noteId.length || !imageUrlCache.count) return;
    NSString *prefix = [noteId stringByAppendingString:@"_"];
    for (NSString *k in [imageUrlCache allKeys]) {
        if ([k hasPrefix:prefix]) [imageUrlCache removeObjectForKey:k];
    }
}

static void RNTCachePut(NSString *noteId, long long index, id url, id liveVideo, id liveImage) {
    NSString *key = RNTCacheKey(noteId, index);
    if (!key) return;
    if (gLastNoteId.length && ![gLastNoteId isEqualToString:noteId]) {
        RNTCacheEvictNote(gLastNoteId);
    }
    NSMutableDictionary *entry = [imageUrlCache[key] mutableCopy] ?: [NSMutableDictionary dictionary];
    NSString *u = RNTPlainURL(url);
    NSString *v = RNTURLString(liveVideo);
    NSString *i = RNTPlainURL(liveImage);
    if (u.length) entry[@"url"] = u;
    if (v.length) entry[@"liveVideo"] = v;
    if (i.length) entry[@"liveImage"] = i;
    if (entry.count) {
        imageUrlCache[key] = entry;
        gLastNoteId = [noteId copy];
    }
}

static BOOL RNTOwnedByOtherIndex(NSString *noteId, long long index, NSString *field, NSString *value) {
    if (!noteId.length || !value.length) return NO;
    NSString *selfKey = RNTCacheKey(noteId, index);
    NSString *prefix = [noteId stringByAppendingString:@"_"];
    for (NSString *k in imageUrlCache) {
        if ([k isEqualToString:selfKey] || ![k hasPrefix:prefix]) continue;
        if ([imageUrlCache[k][field] isEqualToString:value]) return YES;
    }
    return NO;
}

static void RNTCacheCell(id cell, NSString *noteId, long long index) {
    if (!cell) return;
    if (!noteId.length) noteId = RNTKVC(cell, @"noteId");
    id asset = RNTKVC(cell, @"asset");
    id pos = RNTKVC(asset, @"position");
    if ([pos respondsToSelector:@selector(longLongValue)]) {
        long long p = [pos longLongValue];
        if (p != 0 && p != index) return;
    }
    NSString *url = RNTPlainURL(RNTKVC(cell, @"url") ?: RNTKVC(cell, @"originalUrl") ?: RNTKVC(cell, @"weakUrl"));
    NSString *live = RNTURLString(RNTKVC(asset, @"livePhotoVideoURL"));
    NSString *liveImg = RNTPlainURL(RNTKVC(asset, @"livePhotoImageURL"));
    if (url.length && RNTOwnedByOtherIndex(noteId, index, @"url", url)) url = nil;
    if (live.length && RNTOwnedByOtherIndex(noteId, index, @"liveVideo", live)) live = nil;
    if (!liveImg.length) liveImg = url;
    if (liveImg.length && RNTOwnedByOtherIndex(noteId, index, @"url", liveImg)) liveImg = nil;
    if (!url.length && !live.length) return;
    RNTCachePut(noteId, index, url, live, liveImg);
}

#pragma mark - HUD

static UIWindow *RNTKeyWindow(void) {
    for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if (scene.activationState != UISceneActivationStateForegroundActive) continue;
        for (UIWindow *w in scene.windows) {
            if (w.isKeyWindow) return w;
        }
    }
    return [UIApplication sharedApplication].windows.firstObject;
}

static void RNTToast(NSString *text) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *window = RNTKeyWindow();
        if (!window) return;
        [[window viewWithTag:kRNTToastTag] removeFromSuperview];
        UILabel *toast = [[UILabel alloc] init];
        toast.tag = kRNTToastTag;
        toast.text = text;
        toast.textColor = UIColor.whiteColor;
        toast.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.72];
        toast.textAlignment = NSTextAlignmentCenter;
        toast.font = [UIFont systemFontOfSize:14];
        toast.layer.cornerRadius = 8;
        toast.clipsToBounds = YES;
        [toast sizeToFit];
        toast.frame = CGRectMake(0, 0, MAX(120, toast.frame.size.width + 28), 36);
        toast.center = CGPointMake(CGRectGetMidX(window.bounds), CGRectGetMidY(window.bounds));
        [window addSubview:toast];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [UIView animateWithDuration:0.25 animations:^{ toast.alpha = 0; } completion:^(BOOL finished) { [toast removeFromSuperview]; }];
        });
    });
}

static UIView *RNTHudBox(void) {
    UIWindow *window = RNTKeyWindow();
    if (!window) return nil;
    [[window viewWithTag:kRNTToastTag] removeFromSuperview];
    UIView *box = [window viewWithTag:kRNTHudTag];
    if (box) return box;
    box = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 220, 92)];
    box.tag = kRNTHudTag;
    box.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.82];
    box.layer.cornerRadius = 12;
    box.clipsToBounds = YES;

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(16, 14, 188, 20)];
    title.tag = kRNTHudTitleTag;
    title.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    title.textColor = UIColor.whiteColor;

    UILabel *sub = [[UILabel alloc] initWithFrame:CGRectMake(16, 36, 188, 16)];
    sub.tag = kRNTHudSubTag;
    sub.font = [UIFont systemFontOfSize:12];
    sub.textColor = [UIColor colorWithWhite:1 alpha:0.7];

    UIView *track = [[UIView alloc] initWithFrame:CGRectMake(16, 58, 188, 4)];
    track.tag = kRNTHudTrackTag;
    track.backgroundColor = [UIColor colorWithWhite:1 alpha:0.18];
    track.layer.cornerRadius = 2;
    track.clipsToBounds = YES;

    UIView *fill = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 0, 4)];
    fill.tag = kRNTHudFillTag;
    fill.backgroundColor = [UIColor colorWithRed:1.0 green:0.141 blue:0.259 alpha:1.0];
    [track addSubview:fill];

    UILabel *pct = [[UILabel alloc] initWithFrame:CGRectMake(16, 66, 188, 16)];
    pct.tag = kRNTHudPctTag;
    pct.font = [UIFont systemFontOfSize:12];
    pct.textColor = [UIColor colorWithWhite:1 alpha:0.7];
    pct.textAlignment = NSTextAlignmentRight;

    [box addSubview:title];
    [box addSubview:sub];
    [box addSubview:track];
    [box addSubview:pct];
    [window addSubview:box];
    return box;
}

static void RNTHudApply(NSString *title, NSString *subtitle, NSInteger percent) {
    UIView *box = RNTHudBox();
    if (!box) return;
    percent = MAX(0, MIN(100, percent));
    UILabel *titleL = [box viewWithTag:kRNTHudTitleTag];
    UILabel *subL = [box viewWithTag:kRNTHudSubTag];
    UIView *track = [box viewWithTag:kRNTHudTrackTag];
    UIView *fill = [box viewWithTag:kRNTHudFillTag];
    UILabel *pctL = [box viewWithTag:kRNTHudPctTag];
    titleL.text = title;
    subL.text = subtitle.length ? subtitle : @"";
    pctL.text = [NSString stringWithFormat:@"%ld%%", (long)percent];
    fill.frame = CGRectMake(0, 0, CGRectGetWidth(track.bounds) * (CGFloat)percent / 100.0, 4);
    box.alpha = 1;
    UIView *host = box.superview;
    if (host) box.center = CGPointMake(CGRectGetMidX(host.bounds), CGRectGetMidY(host.bounds));
}

static void RNTHudShow(RNTHudKind kind, NSString *title, NSString *subtitle, NSInteger percent) {
    dispatch_async(dispatch_get_main_queue(), ^{
        gHudKind = kind;
        gHudGen += 1;
        RNTHudApply(title, subtitle, percent);
    });
}

static void RNTHudUpdate(NSString *title, NSString *subtitle, NSInteger percent) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (gHudKind == RNTHudKindNone) return;
        RNTHudApply(title, subtitle, percent);
    });
}

static void RNTHudFinish(NSString *title) {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSInteger gen = gHudGen;
        gHudKind = RNTHudKindNone;
        RNTHudApply(title, @"", 100);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (gHudGen != gen) return;
            UIView *box = [RNTKeyWindow() viewWithTag:kRNTHudTag];
            [UIView animateWithDuration:0.25 animations:^{ box.alpha = 0; } completion:^(BOOL finished) {
                if (gHudGen != gen) return;
                [box removeFromSuperview];
            }];
        });
    });
}

static void RNTHudSingleStage(NSString *subtitle, NSInteger percent) {
    if (gHudKind != RNTHudKindSingle) return;
    RNTHudUpdate(@"保存中", subtitle, percent);
}

#pragma mark - Save

static void RNTSaveImageData(NSData *data, void (^completion)(BOOL success)) {
    void (^finish)(BOOL) = ^(BOOL ok) {
        if (!completion) return;
        dispatch_async(dispatch_get_main_queue(), ^{ completion(ok); });
    };
    if (!data.length) {
        finish(NO);
        return;
    }
    UIImage *img = [UIImage imageWithData:data];
    RNTHudSingleStage(@"写入相册", 85);
    [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
        if (img) {
            [PHAssetChangeRequest creationRequestForAssetFromImage:img];
        } else {
            [[PHAssetCreationRequest creationRequestForAsset] addResourceWithType:PHAssetResourceTypePhoto data:data options:nil];
        }
    } completionHandler:^(BOOL success, NSError *error) {
        (void)error;
        finish(success);
    }];
}

static void RNTDownload(NSString *urlString, void (^done)(NSData *data)) {
    void (^finish)(NSData *) = ^(NSData *data) {
        if (!done) return;
        dispatch_async(dispatch_get_main_queue(), ^{ done(data); });
    };
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        finish(nil);
        return;
    }
    RNTHudSingleStage(@"下载", 40);
    [[[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        finish((!error && data.length) ? data : nil);
    }] resume];
}

static void RNTDownloadToPath(NSString *urlString, NSString *destPath, void (^completion)(BOOL success)) {
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        if (completion) completion(NO);
        return;
    }
    [[[NSURLSession sharedSession] downloadTaskWithURL:url completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error) {
        if (error || !location) {
            if (completion) completion(NO);
            return;
        }
        NSFileManager *fm = [NSFileManager defaultManager];
        [fm removeItemAtPath:destPath error:nil];
        BOOL ok = [fm moveItemAtURL:location toURL:[NSURL fileURLWithPath:destPath] error:nil];
        if (completion) completion(ok);
    }] resume];
}

static void RNTSaveLivePhoto(NSURL *imageURL, NSURL *videoURL, void (^done)(BOOL ok)) {
    void (^finish)(BOOL) = ^(BOOL ok) {
        if (!done) return;
        dispatch_async(dispatch_get_main_queue(), ^{ done(ok); });
    };
    if (!imageURL || !videoURL) {
        finish(NO);
        return;
    }
    NSString *uuid = [[NSUUID UUID] UUIDString];
    NSString *tempDir = NSTemporaryDirectory();
    NSString *imagePath = [tempDir stringByAppendingPathComponent:[NSString stringWithFormat:@"xhs_lp_%@_img.jpg", uuid]];
    NSString *videoPath = [tempDir stringByAppendingPathComponent:[NSString stringWithFormat:@"xhs_lp_%@_vid.mov", uuid]];
    NSString *outImagePath = [tempDir stringByAppendingPathComponent:[NSString stringWithFormat:@"xhs_lp_%@_out.jpg", uuid]];
    NSString *outVideoPath = [tempDir stringByAppendingPathComponent:[NSString stringWithFormat:@"xhs_lp_%@_out.mov", uuid]];
    RNTHudSingleStage(@"下载", 32);
    RNTDownloadToPath(RNTPlainURL(imageURL) ?: imageURL.absoluteString, imagePath, ^(BOOL imgOK) {
        if (!imgOK) { finish(NO); return; }
        RNTHudSingleStage(@"下载视频", 55);
        RNTDownloadToPath(videoURL.absoluteString, videoPath, ^(BOOL vidOK) {
            if (!vidOK) { finish(NO); return; }
            Class mgr = NSClassFromString(@"XYPKLivePhotoManager");
            if (!mgr) { finish(NO); return; }
            NSURL *outImgURL = [NSURL fileURLWithPath:outImagePath];
            NSURL *outVidURL = [NSURL fileURLWithPath:outVideoPath];
            if ([mgr convertImageToLivePhotoFormatNewWithInputImagePath:imagePath outputImageURL:outImgURL assetID:uuid] != 0) {
                finish(NO);
                return;
            }
            [mgr preConvertVideoToLivePhotoFormatWithInputVideoPath:videoPath outputVideoURL:outVidURL assetID:uuid completion:^(BOOL cvtOK) {
                if (!cvtOK) { finish(NO); return; }
                RNTHudSingleStage(@"写入相册", 85);
                [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
                    PHAssetCreationRequest *req = [PHAssetCreationRequest creationRequestForAsset];
                    PHAssetResourceCreationOptions *opts = [[PHAssetResourceCreationOptions alloc] init];
                    [req addResourceWithType:PHAssetResourceTypePhoto fileURL:outImgURL options:opts];
                    [req addResourceWithType:PHAssetResourceTypePairedVideo fileURL:outVidURL options:opts];
                } completionHandler:^(BOOL success, NSError *error) {
                    (void)error;
                    NSFileManager *fm = [NSFileManager defaultManager];
                    [fm removeItemAtPath:imagePath error:nil];
                    [fm removeItemAtPath:videoPath error:nil];
                    [fm removeItemAtPath:outImagePath error:nil];
                    [fm removeItemAtPath:outVideoPath error:nil];
                    finish(success);
                }];
            }];
        });
    });
}

static void RNTSaveFromInfo(id info, void (^done)(BOOL ok)) {
    NSString *cached = nil;
    if (gLastNoteId) cached = imageUrlCache[RNTCacheKey(gLastNoteId, gPendingSaveIndex)][@"url"];
    NSString *url = RNTBestImageURL(RNTKVC(info, @"original"))
        ?: RNTBestImageURL(RNTKVC(info, @"url8k"))
        ?: RNTBestImageURL(RNTKVC(info, @"urlLarge"))
        ?: RNTBestImageURL(cached)
        ?: RNTBestImageURL(RNTKVC(info, @"url"))
        ?: RNTBestImageURL(RNTKVC(info, @"livePhotoUrl"));
    NSString *live = RNTURLString(RNTKVC(info, @"livePhotoVideoUrl"));
    NSString *liveImg = RNTBestImageURL(RNTKVC(info, @"livePhotoUrl")) ?: url;
    if (live.length && liveImg.length) {
        RNTSaveLivePhoto([NSURL URLWithString:liveImg], [NSURL URLWithString:live], done);
        return;
    }
    if (url.length) {
        RNTDownload(url, ^(NSData *data) { RNTSaveImageData(data, done); });
        return;
    }
    if (done) done(NO);
}

#pragma mark - Long-press save item

static BOOL RNTIsSaveMenuItem(id item) {
    NSString *type = RNTKVC(item, @"type") ?: @"";
    NSString *title = RNTKVC(item, @"title") ?: @"";
    id text = RNTKVC(item, @"text");
    NSString *textTitle = RNTKVC(text, @"title") ?: RNTKVC(text, @"text") ?: RNTKVC(text, @"content") ?: @"";
    NSString *blob = [[NSString stringWithFormat:@"%@ %@ %@", type, title, textTitle] lowercaseString];
    return [blob containsString:@"save"] || [blob containsString:@"保存"];
}

static void RNTUngrayView(UIView *view) {
    if (!view) return;
    view.alpha = 1;
    view.userInteractionEnabled = YES;
    view.tintAdjustmentMode = UIViewTintAdjustmentModeNormal;
    if ([view isKindOfClass:[UITableViewCell class]]) {
        UITableViewCell *cell = (UITableViewCell *)view;
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        cell.contentView.alpha = 1;
        cell.contentView.userInteractionEnabled = YES;
    }
    if ([view isKindOfClass:[UILabel class]]) {
        UILabel *label = (UILabel *)view;
        if (label.text.length && ([label.text containsString:@"保存"] || [[label.text lowercaseString] containsString:@"save"])) {
            label.alpha = 1;
            label.enabled = YES;
            label.textColor = [UIColor colorWithWhite:0.1 alpha:1];
        }
    }
    for (UIView *sub in view.subviews) RNTUngrayView(sub);
}

static UIButton *RNTMakeCapsule(NSInteger tag, NSString *title, id target, SEL action) {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.tag = tag;
    btn.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.55];
    btn.layer.cornerRadius = kRNTBtnH / 2.0;
    btn.clipsToBounds = YES;
    btn.exclusiveTouch = YES;
    btn.tintColor = UIColor.whiteColor;
    btn.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:12 weight:UIImageSymbolWeightMedium];
    [btn setImage:[UIImage systemImageNamed:@"photo" withConfiguration:config] forState:UIControlStateNormal];
    [btn setTitle:title forState:UIControlStateNormal];
    [btn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    btn.imageEdgeInsets = UIEdgeInsetsMake(0, -1, 0, 3);
    btn.titleEdgeInsets = UIEdgeInsetsMake(0, 3, 0, 0);
    [btn addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    return btn;
}

#pragma mark - Native save flags

%hook XYPHMediaSaveConfig
- (bool)disableSave { return NO; }
- (bool)disableWatermark { return YES; }
- (bool)disableWeiboCover { return YES; }
- (void)setDisableSave:(bool)value { %orig(NO); }
- (void)setDisableWatermark:(bool)value { %orig(YES); }
- (void)setDisableWeiboCover:(bool)value { %orig(YES); }
%end

%hook XYPHBaseNote
- (BOOL)modelCustomTransformFromDictionary:(id)dict {
    BOOL ok = %orig;
    if (self.mediaSaveConfig) self.mediaSaveConfig.disableSave = NO;
    return ok;
}
- (XYPHMediaSaveConfig *)mediaSaveConfig {
    XYPHMediaSaveConfig *cfg = %orig;
    if (cfg) cfg.disableSave = NO;
    return cfg;
}
%end

%hook _TtC18XYNegativeFeedback18LongPressPanelItem
- (bool)isGray {
    if (RNTIsSaveMenuItem(self)) return NO;
    return %orig;
}
- (void)setIsGray:(bool)value {
    %orig(RNTIsSaveMenuItem(self) ? NO : value);
}
- (NSNumber *)_disable {
    if (RNTIsSaveMenuItem(self)) return @0;
    return %orig;
}
- (void)set_disable:(NSNumber *)value {
    %orig(RNTIsSaveMenuItem(self) ? @0 : value);
}
- (NSArray *)disableShow {
    if (RNTIsSaveMenuItem(self)) return @[];
    return %orig;
}
%end

%hook _TtC12XYNoteModule29XYIMediaBrowserLongPressPanel
- (id)tableView:(id)tableView cellForRowAtIndexPath:(id)indexPath {
    id cell = %orig;
    if ([cell isKindOfClass:[UIView class]]) RNTUngrayView(cell);
    return cell;
}
- (_Bool)tableView:(id)tableView shouldHighlightRowAtIndexPath:(id)indexPath {
    return YES;
}
%end

%hook XYVFVideoDownloaderManager
- (bool)disableWatermark { return YES; }
- (void)setDisableWatermark:(bool)value { %orig(YES); }
%end

%hook _TtC12XYNoteModule16ImageSaveService
- (void)saveImageAt:(long long)index from:(id)source disableWatermark:(bool)disableWatermark completion:(id)completion {
    gPendingSaveIndex = index;
    %orig(index, source, YES, completion);
}
- (void)saveImageWithoutManualTrackAt:(long long)index from:(id)source disableWatermark:(bool)disableWatermark completion:(id)completion {
    %orig(index, source, YES, completion);
}
- (void)showDisableResultWithMsg:(id)msg {
    if (gInterceptingNativeSave) return;
    %orig;
}
- (void)saveAssetWithImageInfo:(id)info userId:(id)userId disableWatermark:(bool)disableWatermark {
    NSString *noteId = RNTKVC(info, @"noteId") ?: gLastNoteId;
    RNTCachePut(noteId, gPendingSaveIndex,
                RNTKVC(info, @"url") ?: RNTKVC(info, @"urlLarge") ?: RNTKVC(info, @"original"),
                RNTKVC(info, @"livePhotoVideoUrl"),
                RNTKVC(info, @"url"));
    gInterceptingNativeSave = YES;
    RNTHudShow(RNTHudKindSingle, @"保存中", @"准备", 8);
    RNTSaveFromInfo(info, ^(BOOL ok) {
        gInterceptingNativeSave = NO;
        RNTHudFinish(ok ? @"已保存" : @"保存失败");
    });
}
- (void)saveWithImageInfo:(id)info userId:(id)userId disableWatermark:(bool)disableWatermark startTime:(double)startTime fromLivePhotoFallback:(bool)fallback {
    %orig(info, userId, YES, startTime, fallback);
}
- (void)saveImageListFrom:(id)source disableWatermark:(bool)disableWatermark saveAllCompletion:(id)completion {
    %orig(source, YES, completion);
}
- (void)saveNoteAllImageWithImageList:(id)list disableWatermark:(bool)disableWatermark saveAllCompletion:(id)completion {
    %orig(list, YES, completion);
}
- (void)requestLivePhotoWatermarkWithImageInfo:(id)info userId:(id)userId disableWatermark:(bool)disableWatermark startTime:(double)startTime {
    %orig(info, userId, YES, startTime);
}
- (void)saveLivePhotoWatermarkWithLivePhotoVideoURL:(id)url imageInfo:(id)info userId:(id)userId disableWatermark:(bool)disableWatermark startTime:(double)startTime {
    %orig(url, info, userId, YES, startTime);
}
- (void)saveLivePhotoWatermarkOptWithLivePhotoVideoURL:(id)url imageInfo:(id)info userId:(id)userId disableWatermark:(bool)disableWatermark startTime:(double)startTime {
    %orig(url, info, userId, YES, startTime);
}
- (void)saveLivePhotoDiskEnableLoadWithLivePhotoVideoURL:(id)url imageInfo:(id)info userId:(id)userId disableWatermark:(bool)disableWatermark startTime:(double)startTime {
    %orig(url, info, userId, YES, startTime);
}
- (void)saveLivePhotoFromCacheWithLivePhotoInfo:(id)liveInfo imageInfo:(id)info userId:(id)userId disableWatermark:(bool)disableWatermark startTime:(double)startTime {
    %orig(liveInfo, info, userId, YES, startTime);
}
%end

#pragma mark - Live Photo URL

%hook XYPHNoteImageInfo
- (id)livePhotoVideoInfo {
    id videoInfo = %orig;
    NSString *fileId = RNTKVC(self, @"livePhotoVideoFileId") ?: RNTKVC(self, @"fileId");
    NSString *direct = RNTKVC(self, @"livePhotoVideoUrl");
    if (fileId && [direct isKindOfClass:[NSString class]] && direct.length) {
        livePhotoUrlCache[fileId] = direct;
    }
    if (fileId && videoInfo) {
        NSString *fromJson = RNTStreamURL(RNTKVC(videoInfo, @"mediaInfoJson"));
        if (!fromJson) fromJson = RNTStreamURL(RNTKVC(RNTKVC(videoInfo, @"media"), @"stream"));
        if (fromJson) livePhotoUrlCache[fileId] = fromJson;
    }
    return videoInfo;
}
%end

%hook _TtC11XYNoteBasic7IBAsset
- (void)setLivePhotoVideoURL:(NSURL *)url {
    NSString *fileId = RNTKVC(self, @"livePhotoVideoFileId");
    NSString *cached = fileId ? livePhotoUrlCache[fileId] : nil;
    if (cached) {
        NSURL *n = [NSURL URLWithString:cached];
        if (n) { %orig(n); return; }
    }
    %orig(url);
}
- (NSURL *)livePhotoVideoURL {
    NSURL *url = %orig;
    NSString *fileId = RNTKVC(self, @"livePhotoVideoFileId");
    NSString *cached = fileId ? livePhotoUrlCache[fileId] : nil;
    if (cached) {
        NSURL *n = [NSURL URLWithString:cached];
        if (n) return n;
    }
    return url;
}
%end

%hook _TtC9XYPostKit35PostFlowLivePhotoWatermarkOperation
- (id)initWithSaveAsLivePhoto:(bool)saveAsLivePhoto livePhotoVideoPath:(id)videoPath sessionId:(id)sessionId disableWatermarkWhenSavingAlbum:(bool)disableWatermark completion:(id)completion {
    return %orig(saveAsLivePhoto, videoPath, sessionId, YES, completion);
}
%end

%hook XYPKPostModel
- (bool)disableWatermarkWhenSavingAlbum { return YES; }
- (void)setDisableWatermarkWhenSavingAlbum:(bool)value { %orig(YES); }
%end

#pragma mark - Comments

%hook XYImageCommentManager
- (void)saveImageWithUrl:(id)url authorId:(id)authorId {
    [self downloadWithWatermark:url completion:^(UIImage *image) {
        if (image) {
            RNTSaveImageData(UIImageJPEGRepresentation(image, 0.95), ^(BOOL ok) {
                [self showResultWithIsSuccess:ok];
            });
        } else {
            [self showResultWithIsSuccess:NO];
        }
    }];
}
- (id)createFullWatermarkWith:(id)image userId:(id)userId scale:(double)scale { return nil; }
- (id)createFullWatermarkWith:(id)image userId:(id)userId scale:(double)scale hasAigc:(bool)hasAigc { return nil; }
- (void)saveWithImage:(id)image to:(id)to and:(id)andParam filter:(id)filter data:(id)data cacheKey:(id)cacheKey isHdr:(bool)isHdr {
    if (image) {
        RNTSaveImageData(UIImageJPEGRepresentation(image, 0.95), ^(BOOL ok) {
            [self showResultWithIsSuccess:ok];
        });
    }
}
%end

%hook XYPHNoteComment
- (void)setCommentImages:(NSArray *)commentImages {
    %orig;
    for (id item in commentImages) {
        NSString *videoId = RNTKVC(item, @"livePhotoVideoId");
        NSString *url = RNTStreamURL(RNTKVC(item, @"livePhotoMediaInfo"));
        if (videoId && url) commentLivePhotoCache[videoId] = url;
    }
}
%end

%hook XYCommentImageItem
- (NSString *)livePhotoMediaInfo {
    NSString *mediaInfo = %orig;
    NSString *videoId = RNTKVC(self, @"livePhotoVideoId");
    NSString *url = RNTStreamURL(mediaInfo);
    if (videoId && url) commentLivePhotoCache[videoId] = url;
    return mediaInfo;
}
%end

%hook _TtC12XYNoteModule23CommentMediaSaveService
- (void)saveLivePhotoWithNoteId:(id)noteId commentId:(id)commentId userId:(id)userId imageUrlString:(id)imageUrlString inputVideoId:(id)inputVideoId {
    NSString *cachedUrl = inputVideoId ? commentLivePhotoCache[inputVideoId] : nil;
    if (cachedUrl && imageUrlString) {
        NSString *jpg = RNTPlainURL(imageUrlString) ?: imageUrlString;
        RNTSaveLivePhoto([NSURL URLWithString:jpg], [NSURL URLWithString:cachedUrl], ^(BOOL ok) {
            [self showResultWithIsSuccess:ok];
        });
        return;
    }
    %orig;
}
%end

#pragma mark - Meme

%hook _TtCC12XYNoteModule25MemePreviewPageController13AddMemeButton
- (void)didMoveToSuperview {
    %orig;
    if ([self superview]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self xhs_addSaveButton];
        });
    }
}

%new
- (void)xhs_addSaveButton {
    UIView *superview = [self superview];
    if (!superview || [superview viewWithTag:88888]) return;
    UIButton *saveBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    saveBtn.tag = 88888;
    saveBtn.backgroundColor = [UIColor xy_colorWithHex:0xF2324B];
    saveBtn.layer.cornerRadius = self.layer.cornerRadius;
    saveBtn.clipsToBounds = YES;
    saveBtn.titleLabel.font = self.titleLabel.font;
    [saveBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [saveBtn setTitle:@"保存表情" forState:UIControlStateNormal];
    CGRect addBtnFrame = self.frame;
    saveBtn.frame = CGRectMake(addBtnFrame.origin.x,
                               addBtnFrame.origin.y - addBtnFrame.size.height - 12,
                               addBtnFrame.size.width,
                               addBtnFrame.size.height);
    [saveBtn addTarget:self action:@selector(xhs_saveMeme) forControlEvents:UIControlEventTouchUpInside];
    [superview addSubview:saveBtn];
}

%new
- (void)xhs_saveMeme {
    UIView *superview = self.superview;
    UIImageView *memeImageView = nil;
    for (UIView *view in superview.subviews) {
        if ([NSStringFromClass([view class]) containsString:@"MemeImageView"]) {
            memeImageView = (UIImageView *)view;
            break;
        }
    }
    if (!memeImageView) memeImageView = [self xhs_findImageViewInView:superview];
    if (memeImageView.image) {
        UIImageWriteToSavedPhotosAlbum(memeImageView.image, self, @selector(xhs_image:didFinishSavingWithError:contextInfo:), nil);
        return;
    }
    UIResponder *responder = self;
    while (responder) {
        if ([NSStringFromClass([responder class]) containsString:@"MemePreviewPageController"]) {
            UIImage *cachedImage = RNTKVC(responder, @"cachedImage");
            if (cachedImage) {
                UIImageWriteToSavedPhotosAlbum(cachedImage, self, @selector(xhs_image:didFinishSavingWithError:contextInfo:), nil);
                return;
            }
            NSURL *memeUrl = RNTKVC(responder, @"memeUrl");
            if (memeUrl) {
                [self xhs_showToast:@"正在保存..."];
                RNTDownload(RNTURLString(memeUrl), ^(NSData *data) {
                    if (!data) { [self xhs_showToast:@"保存失败"]; return; }
                    UIImage *image = [UIImage imageWithData:data];
                    if (image) {
                        UIImageWriteToSavedPhotosAlbum(image, self, @selector(xhs_image:didFinishSavingWithError:contextInfo:), nil);
                    } else {
                        RNTSaveImageData(data, ^(BOOL ok) { [self xhs_showToast:ok ? @"已保存到相册" : @"保存失败"]; });
                    }
                });
                return;
            }
        }
        responder = responder.nextResponder;
    }
    [self xhs_showToast:@"保存失败"];
}

%new
- (UIImageView *)xhs_findImageViewInView:(UIView *)view {
    for (UIView *subview in view.subviews) {
        NSString *name = NSStringFromClass([subview class]);
        if (([name containsString:@"MemeImageView"] || [name containsString:@"AnimatedImageView"]) &&
            [subview isKindOfClass:[UIImageView class]] && ((UIImageView *)subview).image) {
            return (UIImageView *)subview;
        }
        UIImageView *found = [self xhs_findImageViewInView:subview];
        if (found) return found;
    }
    return nil;
}

%new
- (void)xhs_image:(UIImage *)image didFinishSavingWithError:(NSError *)error contextInfo:(void *)contextInfo {
    [self xhs_showToast:error ? @"保存失败" : @"已保存到相册"];
}

%new
- (void)xhs_showToast:(NSString *)message { RNTToast(message); }
%end

#pragma mark - Image browser

%hook _TtC11XYNoteBasic11IBViewModel
- (void)recordImageLoadFirstStartWithIndex:(long long)index url:(id)url {
    NSString *noteId = RNTKVC(RNTKVC(self, @"imageBrowser"), @"noteId") ?: RNTKVC(self, @"imageLoadFirstBindNoteId");
    RNTCachePut(noteId, index, url, nil, nil);
    %orig;
}
%end

%hook _TtC11XYNoteBasic12ImageBrowser
- (void)didMoveToSuperview {
    %orig;
    if (self.superview) [self xhs_installButtons];
}

- (void)layoutSubviews {
    %orig;
    [self xhs_installButtons];
    [self xhs_layoutButtons];
}

- (void)collectionView:(UICollectionView *)collectionView willDisplayCell:(UICollectionViewCell *)cell forItemAtIndexPath:(NSIndexPath *)indexPath {
    %orig;
    RNTCacheCell(cell, self.noteId, indexPath.item);
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *bar = [self viewWithTag:kRNTBarTag];
    if (bar && !bar.hidden && bar.alpha > 0.05) {
        CGPoint p = [bar convertPoint:point fromView:self];
        if (CGRectContainsPoint(CGRectInset(bar.bounds, -12, -12), p)) {
            UIView *hit = [bar hitTest:p withEvent:event];
            return hit ?: bar;
        }
    }
    return %orig;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    UIView *bar = [self viewWithTag:kRNTBarTag];
    UIView *v = touch.view;
    while (v) {
        if (v == bar || v.tag == kRNTBarTag || v.tag == kRNTOneTag || v.tag == kRNTAllTag) return NO;
        v = v.superview;
    }
    return %orig;
}

- (void)_hidIndicator {
    %orig;
    UIView *bar = [self viewWithTag:kRNTBarTag];
    if (bar) {
        bar.hidden = NO;
        bar.alpha = 1;
        [self bringSubviewToFront:bar];
    }
}

%new
- (void)xhs_installButtons {
    UIView *old = [self viewWithTag:kRNTBarTag];
    UIButton *existing = [old viewWithTag:kRNTOneTag];
    UIButton *existingAll = [old viewWithTag:kRNTAllTag];
    BOOL same = old
        && [[existing titleForState:UIControlStateNormal] isEqualToString:@"单张"]
        && CGRectGetWidth(existing.frame) == kRNTBtnW
        && CGRectGetHeight(existing.frame) == kRNTBtnH
        && CGRectGetMinX(existingAll.frame) > 1;
    if (same) return;
    [old removeFromSuperview];

    UIView *bar = [[UIView alloc] init];
    bar.tag = kRNTBarTag;
    bar.userInteractionEnabled = YES;
    bar.exclusiveTouch = YES;
    UIButton *one = RNTMakeCapsule(kRNTOneTag, @"单张", self, @selector(xhs_saveCurrent));
    UIButton *all = RNTMakeCapsule(kRNTAllTag, @"全部", self, @selector(xhs_saveAll));
    one.frame = CGRectMake(0, 0, kRNTBtnW, kRNTBtnH);
    all.frame = CGRectMake(kRNTBtnW + kRNTGap, 0, kRNTBtnW, kRNTBtnH);
    bar.frame = CGRectMake(0, 0, kRNTBtnW * 2.0 + kRNTGap, kRNTBtnH);
    [bar addSubview:one];
    [bar addSubview:all];
    [self addSubview:bar];
}

%new
- (void)xhs_layoutButtons {
    UIView *bar = [self viewWithTag:kRNTBarTag];
    if (!bar) return;
    UIButton *one = [bar viewWithTag:kRNTOneTag];
    UIButton *all = [bar viewWithTag:kRNTAllTag];
    one.frame = CGRectMake(0, 0, kRNTBtnW, kRNTBtnH);
    all.frame = CGRectMake(kRNTBtnW + kRNTGap, 0, kRNTBtnW, kRNTBtnH);
    CGFloat barW = kRNTBtnW * 2.0 + kRNTGap;
    CGFloat barH = kRNTBtnH;
    CGFloat insetB = kRNTBarBottom;
    if (@available(iOS 11.0, *)) {
        insetB = MAX(kRNTBarBottom, self.safeAreaInsets.bottom + 12.0);
    }
    CGFloat x = (self.bounds.size.width - barW) / 2.0;
    CGFloat y = self.bounds.size.height - insetB - barH;
    if (x < 8) x = 8;
    if (y < 8) y = 8;
    bar.frame = CGRectMake(x, y, barW, barH);
    bar.hidden = NO;
    bar.alpha = 1;
    [self bringSubviewToFront:bar];
}

%new
- (long long)xhs_currentIndex {
    long long idx = self.displayIndex;
    if (idx < 0 || idx > 100000) idx = self.vm.anchor;
    if (idx < 0) idx = 0;
    return idx;
}

%new
- (void)xhs_saveCurrent {
    RNTHudShow(RNTHudKindSingle, @"保存中", @"准备", 8);
    [self xhs_saveIndex:[self xhs_currentIndex] waitScroll:YES completion:^(BOOL ok) {
        RNTHudFinish(ok ? @"已保存" : @"保存失败");
    }];
}

%new
- (void)xhs_saveAll {
    long long amount = self.vm.imageAmount > 0 ? self.vm.imageAmount : self.vm.amount;
    if (amount <= 0) amount = [self.collection numberOfItemsInSection:0];
    if (amount <= 0) {
        RNTToast(@"没有可保存的图片");
        return;
    }
    RNTHudShow(RNTHudKindBatch, @"批量保存", [NSString stringWithFormat:@"0 / %lld", amount], 0);
    [self xhs_saveAllStep:0 amount:amount ok:0 fail:0];
}

%new
- (void)xhs_saveAllStep:(long long)index amount:(long long)amount ok:(long long)okN fail:(long long)failN {
    if (index >= amount) {
        NSString *msg = failN == 0
            ? [NSString stringWithFormat:@"已保存 %lld 张", okN]
            : [NSString stringWithFormat:@"完成 %lld 成功 / %lld 失败", okN, failN];
        RNTHudFinish(msg);
        return;
    }
    NSInteger pct = (NSInteger)llround((double)index / (double)amount * 100.0);
    if (pct < 4) pct = 4;
    RNTHudUpdate(@"批量保存", [NSString stringWithFormat:@"%lld / %lld", index + 1, amount], pct);
    __weak typeof(self) weakSelf = self;
    [self xhs_saveIndex:index waitScroll:YES completion:^(BOOL success) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf xhs_saveAllStep:index + 1 amount:amount ok:okN + (success ? 1 : 0) fail:failN + (success ? 0 : 1)];
    }];
}

%new
- (void)xhs_saveIndex:(long long)index waitScroll:(BOOL)wait completion:(void (^)(BOOL success))completion {
    NSString *noteId = self.noteId;
    NSIndexPath *path = [NSIndexPath indexPathForItem:index inSection:0];
    id cell = [self.collection cellForItemAtIndexPath:path];
    RNTCacheCell(cell, noteId, index);
    NSDictionary *cached = noteId ? imageUrlCache[RNTCacheKey(noteId, index)] : nil;

    void (^finishWith)(NSString *, NSString *, NSString *) = ^(NSString *url, NSString *liveVideo, NSString *liveImage) {
        if (liveVideo.length && liveImage.length) {
            RNTSaveLivePhoto([NSURL URLWithString:liveImage], [NSURL URLWithString:liveVideo], completion);
            return;
        }
        if (url.length) {
            RNTDownload(url, ^(NSData *data) { RNTSaveImageData(data, completion); });
            return;
        }
        UIImage *img = RNTKVC(cell, @"image");
        if (![img isKindOfClass:[UIImage class]]) {
            img = RNTKVC([self.collection cellForItemAtIndexPath:path], @"image");
        }
        if ([img isKindOfClass:[UIImage class]]) {
            RNTSaveImageData(UIImageJPEGRepresentation(img, 0.95), completion);
            return;
        }
        if (completion) completion(NO);
    };

    if (cached[@"url"] || cached[@"liveVideo"]) {
        finishWith(cached[@"url"], cached[@"liveVideo"], cached[@"liveImage"] ?: cached[@"url"]);
        return;
    }

    if (wait) {
        @try { if ([self.vm respondsToSelector:@selector(scrollTo:)]) [self.vm scrollTo:index]; } @catch (NSException *e) {}
        @try { if ([self respondsToSelector:@selector(scrollTo:)]) [self scrollTo:index]; } @catch (NSException *e) {}
        UICollectionView *c = self.collection;
        if (c && index >= 0 && index < [c numberOfItemsInSection:0]) {
            [c scrollToItemAtIndexPath:path atScrollPosition:UICollectionViewScrollPositionCenteredHorizontally animated:NO];
            [c layoutIfNeeded];
        }
        __block NSInteger tries = 0;
        __block void (^poll)(void) = nil;
        __block __weak void (^weakPoll)(void) = nil;
        poll = ^{
            tries++;
            RNTCacheCell([self.collection cellForItemAtIndexPath:path], noteId, index);
            NSDictionary *again = noteId ? imageUrlCache[RNTCacheKey(noteId, index)] : nil;
            if (again[@"url"] || again[@"liveVideo"] || tries >= 10) {
                [self xhs_saveIndex:index waitScroll:NO completion:completion];
                return;
            }
            void (^next)(void) = weakPoll;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.16 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if (next) next();
            });
        };
        poll = [poll copy];
        weakPoll = poll;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.22 * NSEC_PER_SEC)), dispatch_get_main_queue(), poll);
        return;
    }

    finishWith(cached[@"url"], cached[@"liveVideo"], cached[@"liveImage"] ?: cached[@"url"]);
}
%end

%ctor {
    @autoreleasepool {
        livePhotoUrlCache = [NSMutableDictionary dictionary];
        commentLivePhotoCache = [NSMutableDictionary dictionary];
        imageUrlCache = [NSMutableDictionary dictionary];
    }
}
