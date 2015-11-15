
//
//  DisplayAttachFileController.m
//  GuangXiOA
//
//  Created by  on 11-12-27.
//  Copyright (c) 2011年 __MyCompanyName__. All rights reserved.
//

#import "DisplayAttachFileController.h"
#import "FileUtil.h"
#import "ZipFileBrowserController.h"
#import "ShowLocalFileController.h"
#import <Unrar4iOS/Unrar4iOS.h>
#import "ZipArchive.h"
#import "PDFileManager.h"
#import "AttachManageService.h"
#import "SystemConfigContext.h"
#import "ASIFormDataRequest.h"
#import "AppDelegate.h"
#import "ServiceUrlString.h"
#import "MBProgressHUD.h"
#import "ASIHTTPRequest.h"
#import "PDJsonkit.h"

@interface DisplayAttachFileController()

@property(nonatomic,strong) ASINetworkQueue * networkQueue ;
@property(nonatomic,assign) BOOL showZipFile;
@property(nonatomic,strong) NSArray *aryFiles;
@property(nonatomic,strong) NSString *tmpUnZipDir;//解压缩后的临时目录
@property(nonatomic,strong) UIPopoverController *popVc;
@property(nonatomic,strong) UIWebView *webView;
@property(nonatomic,strong) UITableView *listTableView;
@property(nonatomic,strong) NSString *attachURL;
@property(nonatomic,strong) NSString *attachName;

@property (nonatomic,strong) PDFileManager *fileManager;
//添加弹出文件夹选择
@property (nonatomic,strong) MovePopViewController *moveVc;

@property (nonatomic,strong) NSString *savePath;
@property (nonatomic,assign) NSInteger didTag;
@property (nonatomic, strong) UIDocumentInteractionController *docController;
@property (nonatomic, strong)ASIFormDataRequest* request;
@property (nonatomic,strong) MBProgressHUD* HUD;
@property (nonatomic,assign) BOOL isUpLoaddata;

@end

@implementation DisplayAttachFileController

@synthesize webView,progress,labelTip, attachURL,attachName,networkQueue,showZipFile,didTag;
@synthesize aryFiles,tmpUnZipDir,listTableView,savePath;
@synthesize HUD,fileFiles,isUpLoaddata,isFW,isHY;

- (id)initWithNibName:(NSString *)nibNameOrNil fileURL:(NSString *)fileUrl andFileName:(NSString*)fileName
{
    self = [super initWithNibName:nibNameOrNil bundle:nil];
    if (self)
    {
        self.attachURL = fileUrl;
        self.attachName = fileName;
        showZipFile = NO;
        isFW = NO;
        isHY = NO;
    }
    return self;
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
}

- (void)downloadFile
{
    //下载文件到默认文件夹
    NSString *docsDir = self.fileManager.defaultFolderPath;
    NSString *path = [docsDir stringByAppendingPathComponent:attachName];
    self.savePath = path;
    
    //////////////////////////// 任务队列 /////////////////////////////
    if(!networkQueue)
    {
        self.networkQueue = [[ASINetworkQueue alloc] init];
    }
    
    [networkQueue reset];// 队列清零
    [networkQueue setShowAccurateProgress:YES]; // 进度精确显示
    [networkQueue setDelegate:self ]; // 设置队列的代理对象
    ASIHTTPRequest *request;
    
    ///////////////// request for file1 //////////////////////
    request = [ASIHTTPRequest requestWithURL:[NSURL URLWithString:attachURL]]; // 设置文件 1 的 url
    [request setDownloadProgressDelegate:progress]; // 文件 1 的下载进度条
    [request setDownloadDestinationPath:path];
    
    [request setCompletionBlock :^( void ){
        self.navigationItem.rightBarButtonItem.enabled = YES;
        
        //保存到数据库
        AttachModel *aFile = [[AttachModel alloc] init];
        if(!self.attachName || self.attachName.length <= 0)
        {
            aFile.attachName = [NSString stringWithFormat:@"未命名.%@", [path pathExtension]];
        }
        else
        {
            aFile.attachName = self.attachName;
        }
        aFile.attachToken = [[AttachManageService shared] getAttachToken:self.attachURL];
        aFile.attachURL   = self.attachURL;
        aFile.attachType  = [path pathExtension];
        aFile.attachPath  = path;
        aFile.attachSize  = [NSString stringWithFormat:@"%lld", [self.fileManager fileSizeAtPath:path]];
        NSDateFormatter *df = [[NSDateFormatter alloc] init];
        [df setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
        NSDate *now = [NSDate date];
        aFile.createTime = [df stringFromDate:now];
        
        //当前登录用户
        SystemConfigContext *context = [SystemConfigContext sharedInstance];
        NSDictionary *loginUsr = [context getUserInfo];
        aFile.createUser = [loginUsr objectForKey:@"userId"];

        BOOL saveRet = [[AttachManageService shared] saveOneFile:aFile];
        if(saveRet)
        {
            NSLog(@"保存成功!");
        }
        
        // 使用 complete 块，在下载完时做一些事情
        NSString *pathExt = [path pathExtension];
        if([pathExt compare:@"rar" options:NSCaseInsensitiveSearch] == NSOrderedSame || [pathExt compare:@"zip" options:NSCaseInsensitiveSearch] ==NSOrderedSame)
        {
            [self handleZipRarFile:path];
        }
        else
        {
            self.webView = [[UIWebView alloc] initWithFrame:CGRectMake(0, 0, 768, 960)];
            webView.scalesPageToFit = YES;
            [self.view addSubview:webView];
            
            NSURL *url = [[NSURL alloc] initFileURLWithPath:path];
            [webView loadRequest:[NSURLRequest requestWithURL:url]];
        }
    }];
    [request setFailedBlock :^( void ){
        // 使用 failed 块，在下载失败时做一些事情
        self.webView = [[UIWebView alloc] initWithFrame:CGRectMake(0, 0, 768, 960)];
        webView.scalesPageToFit = YES;
        [self.view addSubview:webView];
        [webView loadHTMLString:@"下载文件失败！" baseURL:nil];
    }];
    
    
    [ networkQueue addOperation :request];
    [ networkQueue go ]; // 队列任务开始
}

#pragma mark - View lifecycle

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadData) name:@"word_reload" object:nil];
    
    self.fileManager = [[PDFileManager alloc] init];
    NSMutableArray* navigationItemTool = [[NSMutableArray alloc]init];
    
    //添加到
    UIBarButtonItem *removeButton = [[UIBarButtonItem alloc] initWithTitle:@"添加到" style:UIBarButtonItemStyleBordered target:self action:@selector(addTo:)];
    [navigationItemTool addObject:removeButton];
//    NSLog(@"file%@",self.fileFiles);
    
    //判断是否是word文件
    NSString* fileFilesPostfix = [self.fileFiles objectForKey:@"WDHZ"];
    
    NSLog(@"fileFilesPostfix = %@",fileFilesPostfix);
    
    
  //  if (([fileFilesPostfix isEqualToString:@"doc"]||[fileFilesPostfix isEqualToString:@"docx"])&&(isFW||isHY))
        if (([fileFilesPostfix isEqualToString:@"doc"]||[fileFilesPostfix isEqualToString:@"docx"]))
    {
        //编辑
        UIBarButtonItem *editButton = [[UIBarButtonItem alloc] initWithTitle:@"编辑" style:UIBarButtonItemStyleBordered target:self action:@selector(onEditButtonClicked:)];
        [navigationItemTool addObject:editButton];
        
        //上传
        UIBarButtonItem* upLoad = [[UIBarButtonItem alloc]initWithTitle:@"上传" style:UIBarButtonItemStyleBordered target:self action:@selector(upLoadFiledata)];
        [navigationItemTool addObject:upLoad];
    }
    self.navigationItem.rightBarButtonItems = navigationItemTool;
    self.title = self.attachName;
    
    //计算附件的Token
    NSString *attachToken = [[AttachManageService shared] getAttachToken:self.attachURL];
    AttachModel *attachModel = [[AttachManageService shared] queryByToken:attachToken];
    if(attachModel && attachModel.attachPath)
    {
        removeButton.enabled = YES;
        self.savePath = attachModel.attachPath;
        if([self.fileManager fileExistsAtPath:attachModel.attachPath]&&(isFW||isHY))
        {
            //修改过的 如果附件存在直接打开
            NSString *pathExt = [attachModel.attachPath pathExtension];
            if([pathExt compare:@"rar" options:NSCaseInsensitiveSearch] == NSOrderedSame || [pathExt compare:@"zip" options:NSCaseInsensitiveSearch] == NSOrderedSame)
            {
                [self handleZipRarFile:attachModel.attachPath];
            }
            else
            {
                if(!self.webView)
                {
                    self.webView = [[UIWebView alloc] initWithFrame:CGRectMake(0, 0, 768, 960)];
                    webView.scalesPageToFit = YES;
                    [self.view addSubview:webView];
                }
                
                NSURL *url = [[NSURL alloc] initFileURLWithPath:attachModel.attachPath];
                [self.webView loadRequest:[NSURLRequest requestWithURL:url]];
            }
        }
        else
        {
            [[AttachManageService shared] deleteOneFile:attachModel];
            removeButton.enabled = NO;
            //附件不存在从网络下载
            if(self.attachURL.length > 0)
            {
                [self downloadFile];
            }
        }
    }
    else
    {
        removeButton.enabled = NO;
        //附件不存在从网络下载
        if(self.attachURL.length > 0)
        {
            [self downloadFile];
        }
    }
}

- (void)addTo:(id)sender
{
    if (_popVc)
    {
        [_popVc dismissPopoverAnimated:YES];
    }
    _moveVc = [[MovePopViewController alloc] init];
    NSMutableArray *array = [[NSMutableArray alloc] initWithArray:[self.fileManager directoryListAtPath:self.fileManager.basePath]];
    _moveVc.resultArray = array;
    _moveVc.delegate = self;
    _popVc = [[UIPopoverController alloc] initWithContentViewController:_moveVc];
    [_popVc presentPopoverFromBarButtonItem:sender permittedArrowDirections:UIPopoverArrowDirectionAny animated:YES];
}

- (void)onEditButtonClicked:(id)sender
{
    NSURL *url = [NSURL fileURLWithPath:self.savePath];
    self.docController = [UIDocumentInteractionController interactionControllerWithURL:url];
    [self.docController setDelegate:self];
    [self.docController presentOpenInMenuFromBarButtonItem:sender animated:YES];
}

- (void)upLoadFiledata
{
    NSData *fileData = [NSData dataWithContentsOfFile:self.savePath];
    if (![fileData length])
    {
        UIAlertView* alert = [[UIAlertView alloc]initWithTitle:@"温馨提示" message:@"对不起，没有数据可上传" delegate:self cancelButtonTitle:nil otherButtonTitles:@"确定", nil];
        [alert show];
        return;
    }
    
    self.progress.hidden = NO;
    [UIApplication sharedApplication].networkActivityIndicatorVisible = YES;
    if (isFW) {
        NSMutableDictionary *params = [NSMutableDictionary dictionaryWithCapacity:5];
        [params setObject:@"UPLOAD_FWFJ" forKey:@"service"];
        NSString *strUrl = [ServiceUrlString generateUrlByParameters:params];
        
        NSURL *url =[ NSURL URLWithString:strUrl];
        self.request = [ASIFormDataRequest requestWithURL: url];
        [self.request setDefaultResponseEncoding:NSUTF8StringEncoding];
        
        SystemConfigContext* context = [SystemConfigContext sharedInstance];
        NSDictionary* loginUsr = [context getUserInfo];
        [self.request addPostValue:[loginUsr objectForKey:@"userId"] forKey:@"userid"];
        [self.request addPostValue:[loginUsr objectForKey:@"password"]forKey :@"password"];
        [self.request addPostValue:[context getDeviceID] forKey :@"imei"];
        [self.request addPostValue:[context getAppVersion]  forKey :@"version"];
        [self.request addPostValue:@"UPLOAD_FWFJ" forKey :@"service"];
        [self.request setPostValue:self.fileFiles forKey: @"FILE_FIELDS" ];
        [self.request setStringEncoding:NSUTF8StringEncoding];
        
        [self.request setFile:self.savePath forKey:@"path"];
        [self.request setDelegate: self ];
        [self.request setDidFinishSelector: @selector (responseComplete )];
        [self.request setDidFailSelector: @selector (responseFailed)];
        [self.request setUploadProgressDelegate:self.progress];
        [self.request startAsynchronous];

    }else if(isHY)
    {
        NSMutableDictionary *params = [NSMutableDictionary dictionaryWithCapacity:5];
        [params setObject:@"UPLOAD_HYTZFJ" forKey:@"service"];
        NSString *strUrl = [ServiceUrlString generateUrlByParameters:params];
        
        NSURL *url =[ NSURL URLWithString:strUrl];
        self.request = [ASIFormDataRequest requestWithURL: url];
        [self.request setDefaultResponseEncoding:NSUTF8StringEncoding];
        
        SystemConfigContext* context = [SystemConfigContext sharedInstance];
        NSDictionary* loginUsr = [context getUserInfo];
        [self.request addPostValue:[loginUsr objectForKey:@"userId"] forKey:@"userid"];
        [self.request addPostValue:[loginUsr objectForKey:@"password"]forKey :@"password"];
        [self.request addPostValue:[context getDeviceID] forKey :@"imei"];
        [self.request addPostValue:[context getAppVersion]  forKey :@"version"];
        [self.request addPostValue:@"UPLOAD_FWFJ" forKey :@"service"];
        [self.request setPostValue:self.fileFiles forKey: @"FILE_FIELDS" ];
        [self.request setStringEncoding:NSUTF8StringEncoding];
        
        [self.request setFile:self.savePath forKey:@"path"];
        [self.request setDelegate: self ];
        [self.request setDidFinishSelector: @selector (responseComplete )];
        [self.request setDidFailSelector: @selector (responseFailed)];
        [self.request setUploadProgressDelegate:self.progress];
        [self.request startAsynchronous];

    }
}

-(void)requestStarted:(ASIHTTPRequest *)request
{
    isUpLoaddata = YES;
    [NSTimer scheduledTimerWithTimeInterval:15 target:self selector:@selector(upDataError) userInfo:nil repeats:NO];
}

-(void)upDataError
{
    if (HUD&&isUpLoaddata == YES) {
        UIAlertView* alert = [[UIAlertView alloc]initWithTitle:@"温馨提示" message:@"连接出现故障" delegate:self cancelButtonTitle:nil otherButtonTitles:@"确定", nil];
        [alert show];
    }
   
}

-(void)responseComplete
{
//    NSLog(@"request%@",self.request.responseString );
//    UIAlertView* alert = [[UIAlertView alloc]initWithTitle:@"温馨提示" message:@"上传成功" delegate:self cancelButtonTitle:nil otherButtonTitles:@"确定", nil];
//    [alert show];
//    isUpLoaddata = NO;
//
    NSString *str = self.request.responseString;
    self.progress.hidden = YES;
    [UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
    NSDictionary *dic = [str objectFromJSONString];
    if( dic && [[dic objectForKey:@"result"] boolValue])
    {
        [self showAlertMessage:@"文件上传成功!"];
    }
    else
    {
        [self showAlertMessage:@"上传失败!"];
    }

}

-(void)respnoseFailed
{
    [self showAlertMessage:@"上传失败!"];
    [UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
}


-(UIViewController *)documentInteractionControllerViewControllerForPreview:(UIDocumentInteractionController *)controller
{
    return self;
}

- (void)didSelectedRow:(NSInteger)row
{
    didTag = YES;
    NSMutableArray *folderKeys = [[NSMutableArray alloc] initWithArray:[self.fileManager directoryListAtPath:self.fileManager.basePath]];
    if(folderKeys == nil || folderKeys.count == 0)
    {
        [_popVc dismissPopoverAnimated:YES];
        return;
    }
    NSString *string = [folderKeys objectAtIndex:row];
    NSString *selectedRowPath = [self.fileManager.basePath stringByAppendingPathComponent:string];
    NSString *toPath = toPath = [selectedRowPath stringByAppendingPathComponent:self.attachName];
    NSString *toDefaultPath = [self.fileManager.defaultFolderPath stringByAppendingPathComponent:self.attachName];
    if([toPath isEqualToString:toDefaultPath])
    {
        [_popVc dismissPopoverAnimated:YES];
        return;
    }
    
    if([self.fileManager fileExistsAtPath:self.savePath])
    {
        [self.fileManager copyItemFromPath:self.savePath toPath:toPath];
        [self.fileManager removeFileAtPath:self.savePath];
    }
    
    //此处管理附件表中的数据
    if([self.fileManager fileExistsAtPath:toPath])
    {
        //如果文件复制成功，更新索引
        NSString *attachToken = [[AttachManageService shared] getAttachToken:self.attachURL];
        AttachModel *aModel = [[AttachManageService shared] queryByToken:attachToken];
        aModel.attachPath = toPath;
        BOOL updateRet = [[AttachManageService shared] updateOneFile:aModel];
        if(updateRet)
        {
            aModel = [[AttachManageService shared] queryByToken:attachToken];
            DLog(@"更新成功:%@", aModel.attachPath);
        }
    }
    else
    {
        //否则删除数据库文件
        NSString *attachToken = [[AttachManageService shared] getAttachToken:self.attachURL];
        AttachModel *aModel = [[AttachManageService shared] queryByToken:attachToken];
        BOOL deleteRet = [[AttachManageService shared] deleteOneFile:aModel];
        if(deleteRet)
        {
            DLog(@"删除成功:%@", aModel.attachName);
        }
    }
    
    [_popVc dismissPopoverAnimated:YES];
}

- (void)viewWillAppear:(BOOL)animated
{
    [self.navigationController setNavigationBarHidden:NO animated:YES];
    [super viewWillAppear:animated];
}

- (void) viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    if(showZipFile)
    {
        [self.navigationController popViewControllerAnimated:NO];
    }
}

- (void)viewWillDisappear:(BOOL)animated
{
    if (_popVc)
        [_popVc dismissPopoverAnimated:YES];
    [networkQueue cancelAllOperations];
    if (didTag == NO) {
        NSMutableArray *folderKeys = [[NSUserDefaults standardUserDefaults] objectForKey:@"folderKeys"];
        
        if (folderKeys.count > 0 ) {
            
            for (int i = 0;i<folderKeys.count;i++) {
                NSString *string = [folderKeys objectAtIndex:i];
                if ([string isEqualToString:@"默认文件夹"]) {
                    
                    NSArray *array = [[NSUserDefaults standardUserDefaults] objectForKey:string];
                    NSMutableArray *array1 = [[NSMutableArray alloc] initWithArray:array];
                    [array1 addObject:[NSDictionary dictionaryWithObject:self.savePath forKey:attachName]];
                    NSString *key1 = [folderKeys objectAtIndex:i];
                    [[NSUserDefaults standardUserDefaults] setObject:array1 forKey:key1];
                }
            }
        }
    }
    
    [super viewWillDisappear:animated];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
	return (interfaceOrientation == UIInterfaceOrientationPortrait || interfaceOrientation == UIInterfaceOrientationPortraitUpsideDown);
}

- (void)decompressZipFile:(NSString*)path
{
    ZipArchive *zipper = [[ZipArchive alloc] init];
    [zipper UnzipOpenFile:path];
    [zipper UnzipFileTo:tmpUnZipDir overWrite:YES];
    [zipper UnzipCloseFile];
}

- (void)decompressRarFile:(NSString*)path
{
    Unrar4iOS *unrar = [[Unrar4iOS alloc] init];
    
    NSFileManager *fm = [NSFileManager defaultManager ];
    BOOL isDir;
    if(![fm fileExistsAtPath:tmpUnZipDir isDirectory:&isDir])
        [fm createDirectoryAtPath:tmpUnZipDir withIntermediateDirectories:NO attributes:nil error:nil];
    
    BOOL ok = [unrar unrarOpenFile:path];
	if (ok)
    {
        [unrar unrarFileTo:tmpUnZipDir overWrite:YES];
        [unrar unrarCloseFile];
    }
}

- (void)handleZipRarFile:(NSString*)path
{
    NSFileManager *manager = [NSFileManager defaultManager];
    NSDictionary *dicAttr = [manager attributesOfItemAtPath:path error:nil];
    NSNumber *numSize = [dicAttr objectForKey:NSFileSize];
    if([numSize integerValue] > 0)
    {
        self.tmpUnZipDir = [NSTemporaryDirectory()  stringByAppendingPathComponent:[path lastPathComponent]];
        NSString *pathExt = [path pathExtension];
        if([pathExt compare:@"rar" options:NSCaseInsensitiveSearch] == NSOrderedSame)
        {
            [self decompressRarFile:path];
        }
        else if([pathExt compare:@"zip" options:NSCaseInsensitiveSearch] == NSOrderedSame)
        {
            [self decompressZipFile:path];
        }
    }
    else
    {
        [webView loadHTMLString:@"下载文件失败" baseURL:nil];
    }
    NSFileManager *fm = [NSFileManager defaultManager];
    NSMutableArray *ary = [NSMutableArray arrayWithCapacity:20];
    NSArray *aryTmp = [fm contentsOfDirectoryAtPath:tmpUnZipDir error:nil];
    [ary addObjectsFromArray:aryTmp];
    [ary removeObject:@".DS_Store"];
    [ary removeObject:@"__MACOSX"];
    self.aryFiles = ary;
    self.listTableView = [[UITableView alloc] initWithFrame:CGRectMake(0, 0, 768, 960) style:UITableViewStylePlain];
    listTableView.dataSource = self;
    listTableView.delegate = self;
    [self.view addSubview:listTableView];
    [listTableView reloadData];
}

#pragma mark - UIWebView Delegate Method

- (void)webViewDidFinishLoad:(UIWebView *)webView
{
	[UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
}

- (void)webView:(UIWebView *)webview didFailLoadWithError:(NSError *)error
{
	[UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
    [webView loadHTMLString:@"对不起，您所访问的文件不存在" baseURL:nil];
}

#pragma mark - UITableView Delegate Method

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return [aryFiles count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *CellIdentifier = @"Cell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    
    if (cell == nil)
    {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:CellIdentifier];
        cell.textLabel.font = [UIFont fontWithName:@"Helvetica" size:18.0];
        cell.textLabel.numberOfLines = 2;
        
        UIView *bgview = [[UIView alloc] initWithFrame:cell.contentView.frame];
        bgview.backgroundColor = [UIColor colorWithRed:0 green:94.0/255 blue:107.0/255 alpha:1.0];
        cell.selectedBackgroundView = bgview;
    }
    NSString *fileName = [aryFiles objectAtIndex:indexPath.row];
    cell.textLabel.text = fileName;
    NSString *path = [NSString stringWithFormat:@"%@/%@",tmpUnZipDir,fileName];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSError *err;
    NSDictionary *dicAttr = [fm attributesOfItemAtPath:path error:&err];
    if([[dicAttr objectForKey:NSFileType] isEqualToString:NSFileTypeDirectory])
    {
        cell.imageView.image = [UIImage imageNamed:@"folder.png"];
    }
    else
    {
        NSString *pathExt = [fileName pathExtension];
        cell.imageView.image = [FileUtil imageForFileExt:pathExt];
    }
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSString *fileName = [aryFiles objectAtIndex:indexPath.row];
    NSString *path = [NSString stringWithFormat:@"%@/%@",tmpUnZipDir,fileName];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSError *err;
    NSDictionary *dicAttr = [fm attributesOfItemAtPath:path error:&err];
    if([[dicAttr objectForKey:NSFileType] isEqualToString:NSFileTypeDirectory])
    {
        ZipFileBrowserController *detailViewController = [[ZipFileBrowserController alloc] initWithStyle:UITableViewStylePlain andParentDir:path];
        [self.navigationController pushViewController:detailViewController animated:YES];
    }
    else
    {
        ShowLocalFileController *detailViewController = [[ShowLocalFileController alloc] initWithNibName:@"ShowLocalFileController" bundle:nil];
        detailViewController.fullPath = path;
        detailViewController.fileName = fileName;
        detailViewController.bCanSendEmail = NO;
        [self.navigationController pushViewController:detailViewController animated:YES];
    }
}


- (void)reloadData
{
    AppDelegate *app = [UIApplication sharedApplication].delegate;
    if(app.docFileURL)
    {
        NSFileManager *fm = [NSFileManager defaultManager];
        [fm removeItemAtURL:[NSURL fileURLWithPath:self.savePath] error:nil];
        [fm copyItemAtURL:app.docFileURL toURL:[NSURL fileURLWithPath:self.savePath] error:nil];
        NSURLRequest *req = [[NSURLRequest alloc] initWithURL:[NSURL fileURLWithPath:self.savePath]];
        [self.webView loadRequest:req];
    }
}

- (void)showAlertMessage:(NSString*)msg{
    UIAlertView *alert = [[UIAlertView alloc]
                          initWithTitle:@"提示"
                          message:msg
                          delegate:self
                          cancelButtonTitle:@"确定"
                          otherButtonTitles:nil];
    [alert show];
    return;
}


@end
