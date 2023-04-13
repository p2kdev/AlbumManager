#import "Tweak.h"

@implementation AlbumManager

+ (instancetype)sharedInstance {
    static AlbumManager *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];

    if (self) {
        NSFileManager *manager = [NSFileManager defaultManager];
        if(![manager fileExistsAtPath:PREFERENCES_PATH isDirectory:nil]) {
            if(![manager createDirectoryAtPath:PREFERENCES_PATH withIntermediateDirectories:YES attributes:nil error:nil]) {
                NSLog(@"ERROR: Unable to create preferences folder");
                return nil;
            }
        }

        if(![manager fileExistsAtPath:PLIST_PATH isDirectory:nil]) {
            if (![manager createFileAtPath:PLIST_PATH contents:nil attributes:nil]) {
                NSLog(@"ERROR: Unable to create preferences file");
                return nil;
            }

            [[NSDictionary new] writeToURL:[NSURL fileURLWithPath:PLIST_PATH] error:nil];
        }

        _settings = [NSDictionary dictionaryWithContentsOfURL:[NSURL fileURLWithPath:PLIST_PATH] error:nil];
    }

    return self;
}

- (id)objectForKey:(NSString *)key {
    return [_settings objectForKey:key];
}

- (void)setObject:(id)object forKey:(NSString *)key {
    NSMutableDictionary *settings = [_settings mutableCopy];

    [settings setObject:object forKey:key];
    NSError *error;
    [settings writeToURL:[NSURL fileURLWithPath:PLIST_PATH] error:&error];

    _settings = [settings copy];
}

-(void)removeObjectForKey:(NSString *)key {
    NSMutableDictionary *settings = [_settings mutableCopy];

    [settings removeObjectForKey:key];
    [settings writeToURL:[NSURL fileURLWithPath:PLIST_PATH] error:nil];

    _settings = [settings copy];
}

- (NSString *)uuidForCollection:(PHAssetCollection *)collection {
    return collection.cloudGUID ? collection.cloudGUID : collection.uuid;
}

- (void)tryAccessingAlbumWithUUID:(NSString *)uuid WithCompletion:(void (^)(BOOL success))completion {
    NSString *protection = [self objectForKey:uuid];

	if ([protection isEqualToString:@"biometrics"]) {
		[self authenticateWithBiometricsWithCompletion:^(BOOL success) {
            dispatch_async(dispatch_get_main_queue(), ^{
				if (success) completion(YES);
			});
		}];
	} else if (protection != nil) {
		[self authenticateWithPasswordForHash:protection WithCompletion:^(BOOL success) {
			dispatch_async(dispatch_get_main_queue(), ^{
				if (success) completion(YES);
			});
		}];
	} else {
		completion(YES);
	}

    completion(NO);
}

- (void)authenticateWithBiometricsWithCompletion:(void (^)(BOOL success))completion {
    LAContext *context = [[LAContext alloc] init];
    NSError *authError = nil;

    if ([context canEvaluatePolicy:LAPolicyDeviceOwnerAuthenticationWithBiometrics error:&authError]) {
        [context evaluatePolicy:LAPolicyDeviceOwnerAuthenticationWithBiometrics localizedReason:@"View album" reply:^(BOOL success, NSError *error) {
            completion(success);
        }];
    } else {
        NSString *biometryType = context.biometryType == LABiometryTypeFaceID ? @"Face ID" : @"Touch ID";

        UIAlertController *authFailed = [UIAlertController alertControllerWithTitle:@"No authentication method" message:[NSString stringWithFormat:@"%@ is currently unavailable", biometryType] preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction *ok = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleDefault handler:^(UIAlertAction * action) {}];
        [authFailed addAction:ok];

        UIViewController *rootVC = [[[[UIApplication sharedApplication] windows] firstObject] rootViewController];
        [rootVC presentViewController:authFailed animated:YES completion:nil];
        completion(NO);
    }
}

- (void)authenticateWithPasswordForHash:(NSString *)hash WithCompletion:(void (^)(BOOL success))completion {
    UIViewController *rootVC = [[[[UIApplication sharedApplication] windows] firstObject] rootViewController];

    UIAlertController *passwordVC = [UIAlertController alertControllerWithTitle:@"Album Password?" message:nil preferredStyle:UIAlertControllerStyleAlert];
    NSString *requestedKeyboard = [hash substringToIndex:1];
    hash = [hash substringFromIndex:1]; // Remove keyboard indicator from hash

    [passwordVC addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.secureTextEntry = YES;
        textField.autocorrectionType = UITextAutocorrectionTypeNo;
		textField.spellCheckingType = UITextSpellCheckingTypeNo;
        textField.keyboardType = [requestedKeyboard isEqualToString:@"c"] ? UIKeyboardTypeNumberPad : UIKeyboardTypeDefault;
    }];

    UIAlertAction *checkPassword = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){
        NSString *enteredPassword = [passwordVC.textFields[0] text];
        if (enteredPassword.length <= 0) return;

        NSString *passwordHash = [self sha256HashForText:enteredPassword];
        if ([passwordHash isEqualToString:hash]) {
            completion(YES);
        } else {
            passwordVC.textFields[0].text = @"";
            [rootVC presentViewController:passwordVC animated:YES completion:nil];
        }
        
    }];
    UIAlertAction *cancelPassword = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action){}];
    [passwordVC addAction:checkPassword];
    [passwordVC addAction:cancelPassword];

    
    [rootVC presentViewController:passwordVC animated:YES completion:nil];
}

-(NSString*)sha256HashForText:(NSString*)text {
    const char* utf8chars = [text UTF8String];
    unsigned char result[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(utf8chars, (CC_LONG)strlen(utf8chars), result);

    NSMutableString *ret = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH*2];
    for(int i = 0; i<CC_SHA256_DIGEST_LENGTH; i++) {
        [ret appendFormat:@"%02x",result[i]];
    }
    return ret;
}
@end