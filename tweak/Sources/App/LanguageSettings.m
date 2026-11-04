#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "LanguageSettings.h"

SGModRow *SGInterfaceLanguageRow(void) {
    SGModRow *row=SGMenuRow(SGLocalized(@"Language"),@[SGLocalized(@"Device language"),SGLocalized(@"English"),SGLocalized(@"Tiếng Việt")],^NSString *{
        NSString *value=[NSUserDefaults.standardUserDefaults stringForKey:SGKeyUILanguage];
        return [value isEqual:@"vi"]?SGLocalized(@"Tiếng Việt"):[value isEqual:@"en"]?SGLocalized(@"English"):SGLocalized(@"Device language");
    },^(NSInteger index){
        NSString *tag=@[@"auto",@"en",@"vi"][(NSUInteger)index];
        [NSUserDefaults.standardUserDefaults setObject:tag forKey:SGKeyUILanguage];
        UIAlertController *alert=[UIAlertController alertControllerWithTitle:SGLocalized(@"Restart Spotify")
            message:SGLocalized(@"Vitrine interface language. Spotify content and the lyrics translation target stay as selected. Restart Spotify to apply the change everywhere.") preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:SGLocalized(@"Restart now") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){SGRestartSpotify();}]];
        [alert addAction:[UIAlertAction actionWithTitle:SGLocalized(@"Later") style:UIAlertActionStyleCancel handler:nil]];
        [SGTopController() presentViewController:alert animated:YES completion:nil];
    });
    return row;
}
