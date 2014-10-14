//
//  LYRUIConversationNotificationObeserver.m
//  Pods
//
//  Created by Kevin Coleman on 9/20/14.
//
//

#import "LYRUIMessageDataSource.h"
#import "LYRUIDataSourceChange.h"

@interface LYRUIMessageDataSource ()

@property (nonatomic) LYRConversation *conversation;
@property (nonatomic) dispatch_queue_t messageOperationQueue;

@end

@implementation LYRUIMessageDataSource

- (id)initWithClient:(LYRClient *)layerClient conversation:(LYRConversation *)conversation
{
    self = [super init];
    if (self) {
        
        _layerClient = layerClient;
        _conversation = conversation;
        _messages = [self fetchMessages];
        _messageOperationQueue = dispatch_queue_create("com.layer.messageProcess", NULL);
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didReceiveLayerObjectsDidChangeNotification:)
                                                     name:LYRClientObjectsDidChangeNotification
                                                   object:layerClient];
    }
    return self;
}

- (id)init
{
    @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"Failed to call designated initializer." userInfo:nil];
}

- (void)sendMessages:(LYRMessage *)message
{
    dispatch_async(self.messageOperationQueue, ^{
        NSUInteger insertIndex = self.messages.count;
        [self.messages addObject:message];
       
        NSMutableArray *changeObjects = [[NSMutableArray alloc] init];
        [changeObjects addObject:[LYRUIDataSourceChange changeObjectWithType:LYRUIDataSourceChangeTypeInsert newIndex:insertIndex oldIndex:0]];
        [changeObjects addObject:[LYRUIDataSourceChange changeObjectWithType:LYRUIDataSourceChangeTypeUpdate newIndex:insertIndex - 1 oldIndex:0]];
        [self dispatchChanges:changeObjects];
    });
}

- (NSMutableArray *)fetchMessages
{
    return [[[self.layerClient messagesForConversation:self.conversation] array] mutableCopy];
}

- (void)didReceiveLayerObjectsDidChangeNotification:(NSNotification *)notification;
{
    dispatch_async(self.messageOperationQueue, ^{
        NSArray *messageDelta = [self fetchMessages];
        [self processLayerChangeNotification:notification completion:^(NSMutableArray *messageArray) {
            if (messageArray.count > 0) {
                [self processMessageChanges:messageArray withDelta:messageDelta completion:^(NSArray *messageChanges) {
                    [self dispatchChanges:messageChanges];
                }];
            }
        }];
    });
}

- (void)processLayerChangeNotification:(NSNotification *)notification completion:(void(^)(NSMutableArray *messageArray))completion
{
    NSMutableArray *messageArray = [[NSMutableArray alloc] init];
    NSArray *changes = [notification.userInfo objectForKey:LYRClientObjectChangesUserInfoKey];
    for (NSDictionary *change in changes) {
        if ([[change objectForKey:LYRObjectChangeObjectKey]isKindOfClass:[LYRMessage class]]) {
            [messageArray addObject:change];
        }
    }
    completion(messageArray);
}

- (void)processMessageChanges:(NSMutableArray *)messageChanges withDelta:(NSArray *)messageDelta completion:(void(^)(NSArray *messageChanges))completion
{
    NSMutableArray *changeObjects = [[NSMutableArray alloc] init];
    for (NSDictionary *messageChange in messageChanges) {
        LYRMessage *message = [messageChange objectForKey:LYRObjectChangeObjectKey];
        if ([message.conversation.identifier.absoluteString isEqualToString:self.conversation.identifier.absoluteString]) {
            LYRObjectChangeType updateKey = (LYRObjectChangeType)[[messageChange objectForKey:LYRObjectChangeTypeKey] integerValue];
            switch (updateKey) {
                case LYRObjectChangeTypeCreate:
                    break;
                    
                case LYRObjectChangeTypeUpdate: {
                    if ([[messageChange objectForKey:LYRObjectChangePropertyKey] isEqualToString:@"index"]) {
                        NSUInteger oldIndex = [[messageChange objectForKey:LYRObjectChangeOldValueKey] integerValue];
                        NSUInteger newIndex = [[messageChange objectForKey:LYRObjectChangeNewValueKey] integerValue];
                        [changeObjects addObject:[LYRUIDataSourceChange changeObjectWithType:LYRUIDataSourceChangeTypeMove newIndex:newIndex oldIndex:oldIndex]];
                    } else {
                        [changeObjects addObject:[LYRUIDataSourceChange changeObjectWithType:LYRUIDataSourceChangeTypeUpdate newIndex:message.index oldIndex:0]];
                    }
                    break;
                }
                    
                case LYRObjectChangeTypeDelete:
                   [changeObjects addObject:[LYRUIDataSourceChange changeObjectWithType:LYRUIDataSourceChangeTypeInsert newIndex:message.index oldIndex:0]];
                    break;
                    
                default:
                    break;
            }
        }
    }
    self.messages = messageDelta;
    NSLog(@"messages count: %lu", (unsigned long)self.messages.count);
    NSLog(@"Message Changes %@", changeObjects);
    completion(changeObjects);
}

- (void)dispatchChanges:(NSArray *)changes
{
    if (changes.count > 0) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate observer:self updateWithChanges:changes];
        });
    }
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end