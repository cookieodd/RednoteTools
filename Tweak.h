/**
 * RednoteTools 9.52
 */

#ifndef Tweak_h
#define Tweak_h

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <Photos/Photos.h>

@class _TtC11XYNoteBasic12ImageBrowser;

#pragma mark - Note save

@interface XYPHMediaSaveConfig : NSObject
@property (nonatomic) bool disableSave;
@property (nonatomic) bool disableWatermark;
@property (nonatomic) bool disableWeiboCover;
@end

@interface XYPHBaseNote : NSObject
@property (nonatomic, retain) XYPHMediaSaveConfig *mediaSaveConfig;
- (BOOL)modelCustomTransformFromDictionary:(id)dict;
@end

@interface _TtC18XYNegativeFeedback18LongPressPanelItem : NSObject
@property (nonatomic, copy) NSString *type;
@property (nonatomic, copy) NSString *title;
@property (nonatomic) bool isGray;
@property (nonatomic, retain) NSNumber *_disable;
@property (nonatomic, copy) NSArray *disableShow;
@property (nonatomic, retain) id text;
@end

@interface _TtC12XYNoteModule29XYIMediaBrowserLongPressPanel : UIViewController
@end

@interface XYVFVideoDownloaderManager : NSObject
@property (nonatomic) bool disableWatermark;
@end

@interface _TtC12XYNoteModule16ImageSaveService : NSObject
- (void)showDisableResultWithMsg:(id)msg;
- (void)saveImageAt:(long long)index from:(id)source disableWatermark:(bool)disableWatermark completion:(id)completion;
- (void)saveImageWithoutManualTrackAt:(long long)index from:(id)source disableWatermark:(bool)disableWatermark completion:(id)completion;
- (void)saveAssetWithImageInfo:(id)info userId:(id)userId disableWatermark:(bool)disableWatermark;
- (void)saveWithImageInfo:(id)info userId:(id)userId disableWatermark:(bool)disableWatermark startTime:(double)startTime fromLivePhotoFallback:(bool)fallback;
- (void)saveImageListFrom:(id)from disableWatermark:(bool)disableWatermark saveAllCompletion:(id)completion;
- (void)saveNoteAllImageWithImageList:(id)list disableWatermark:(bool)disableWatermark saveAllCompletion:(id)completion;
- (void)requestLivePhotoWatermarkWithImageInfo:(id)info userId:(id)userId disableWatermark:(bool)disableWatermark startTime:(double)startTime;
- (void)saveLivePhotoWatermarkWithLivePhotoVideoURL:(id)url imageInfo:(id)info userId:(id)userId disableWatermark:(bool)disableWatermark startTime:(double)startTime;
- (void)saveLivePhotoWatermarkOptWithLivePhotoVideoURL:(id)url imageInfo:(id)info userId:(id)userId disableWatermark:(bool)disableWatermark startTime:(double)startTime;
- (void)saveLivePhotoDiskEnableLoadWithLivePhotoVideoURL:(id)url imageInfo:(id)info userId:(id)userId disableWatermark:(bool)disableWatermark startTime:(double)startTime;
- (void)saveLivePhotoFromCacheWithLivePhotoInfo:(id)liveInfo imageInfo:(id)info userId:(id)userId disableWatermark:(bool)disableWatermark startTime:(double)startTime;
@end

@interface XYPHNoteImageInfo : NSObject
@property (nonatomic, copy) NSString *fileId;
@property (nonatomic, copy) NSString *url;
@property (nonatomic, copy) NSString *livePhotoVideoFileId;
@property (nonatomic, copy) NSString *livePhotoVideoUrl;
@property (nonatomic, retain) id livePhotoVideoInfo;
@end

@interface _TtC11XYNoteBasic7IBAsset : NSObject
@property (nonatomic, copy) NSString *livePhotoVideoFileId;
@property (nonatomic, copy) NSURL *livePhotoVideoURL;
@property (nonatomic, copy) NSURL *livePhotoImageURL;
@end

@interface _TtC9XYPostKit35PostFlowLivePhotoWatermarkOperation : NSObject
@end

@interface XYPKPostModel : NSObject
@property (nonatomic) bool disableWatermarkWhenSavingAlbum;
@end

#pragma mark - Comments

@interface XYCommentImageItem : NSObject
@property (nonatomic, copy) NSString *url;
@property (nonatomic, copy) NSString *livePhotoMediaInfo;
@property (nonatomic, copy) NSString *livePhotoVideoId;
@end

@interface XYImageCommentManager : NSObject
- (void)downloadWithWatermark:(id)url completion:(void (^)(UIImage *))completion;
- (void)showResultWithIsSuccess:(bool)isSuccess;
@end

@interface XYPHNoteComment : NSObject
@property (nonatomic, copy) NSArray *commentImages;
@end

@interface _TtC12XYNoteModule23CommentMediaSaveService : NSObject
- (void)showResultWithIsSuccess:(bool)isSuccess;
@end

@interface XYPKLivePhotoManager : NSObject
+ (long long)convertImageToLivePhotoFormatNewWithInputImagePath:(id)inputImagePath outputImageURL:(id)outputImageURL assetID:(id)assetID;
+ (void)preConvertVideoToLivePhotoFormatWithInputVideoPath:(id)inputVideoPath outputVideoURL:(id)outputVideoURL assetID:(id)assetID completion:(void (^)(BOOL success))completion;
@end

#pragma mark - Meme

@interface _TtCC12XYNoteModule25MemePreviewPageController13AddMemeButton : UIButton
- (void)xhs_addSaveButton;
- (void)xhs_saveMeme;
- (UIImageView *)xhs_findImageViewInView:(UIView *)view;
- (void)xhs_image:(UIImage *)image didFinishSavingWithError:(NSError *)error contextInfo:(void *)contextInfo;
- (void)xhs_showToast:(NSString *)message;
@end

@interface UIColor (XYHomeModule)
+ (id)xy_colorWithHex:(unsigned int)hex;
@end

#pragma mark - Image browser

@interface _TtC11XYNoteBasic11IBViewModel : NSObject
@property (nonatomic, readonly) long long amount;
@property (nonatomic, readonly) long long imageAmount;
@property (nonatomic) long long anchor;
@property (nonatomic, weak) UICollectionView *collection;
@property (nonatomic, weak) _TtC11XYNoteBasic12ImageBrowser *imageBrowser;
- (void)scrollTo:(long long)to;
@end

@interface _TtC11XYNoteBasic12ImageBrowser : UIView
@property (nonatomic, readonly) NSString *noteId;
@property (nonatomic) long long displayIndex;
@property (nonatomic, retain) UICollectionView *collection;
@property (nonatomic, readonly) _TtC11XYNoteBasic11IBViewModel *vm;
- (void)scrollTo:(long long)to;
- (void)xhs_installButtons;
- (void)xhs_layoutButtons;
- (void)xhs_saveCurrent;
- (void)xhs_saveAll;
- (void)xhs_saveAllStep:(long long)index amount:(long long)amount ok:(long long)okN fail:(long long)failN;
- (long long)xhs_currentIndex;
- (void)xhs_saveIndex:(long long)index waitScroll:(BOOL)wait completion:(void (^)(BOOL success))completion;
@end

#endif /* Tweak_h */
