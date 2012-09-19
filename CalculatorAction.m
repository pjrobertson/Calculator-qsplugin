//
//  CalculatorAction.m
//  Quicksilver
//
// Created by Kevin Ballard, modified by Patrick Robertson
// Copyright QSApp.com 2011

#import "CalculatorAction.h"
#import "CalculatorPrefPane.h"

/* CalculatePrivate.h is from a private framework, reverse engineered by Nicholas Jitkoff.
 There are no guarantees that this will work indefinitely. It may break in a future version of OS X */
#import "CalculatePrivate.h"

// BC/DC Calculator options
#define calculatorEngineDC @"calculatorEngineDC"
#define calculatorEngineBC @"calculatorEngineBC"
#define CalculatorDivider @"\n[=====Calculator Divider=====]\n"


@implementation CalculatorActionProvider

- (id) init {
	if ((self = [super init])) {
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
		[defaults registerDefaults:[NSDictionary dictionaryWithObject:[NSNumber numberWithInteger:0] forKey:kCalculatorDisplayPref]];
        dcStack = [[NSString alloc] initWithString:@""];
	}
	return self;
}

- (void)dealloc {
    if (dcStack) {
        [dcStack release];
    }
    [super dealloc];
}

- (QSObject *)calculate:(QSObject *)dObject {
	
	QSObject *result = [self performCalculation:dObject];
	NSString *outString = [result objectForType:QSTextType];
	
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	
	// Copy the result to the clipboard
	if ([defaults objectForKey:kCalculatorCopyResultToClipboard] && [[defaults objectForKey:kCalculatorCopyResultToClipboard] boolValue]) {
		NSPasteboard *pb = [NSPasteboard generalPasteboard];
		[pb declareTypes:[NSArray arrayWithObject:NSStringPboardType] owner:self];
		[pb setString:outString forType:NSStringPboardType];
	}
	
	
	switch ([[defaults objectForKey:kCalculatorDisplayPref] integerValue]) {
		case CalculatorDisplayNormal:
			// Do nothing - we're popping the result back up
			break;
		case CalculatorDisplayLargeType: {
			// Display result as large type
			QSShowLargeType(outString);
			[[QSReg preferredCommandInterface] selectObject:result];
			result = nil;
			break;
		} case CalculatorDisplayNotification: {
			// Display result as notification
			NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:[QSResourceManager imageNamed:@"com.apple.calculator"], QSNotifierIcon,
										@"Calculation Result", QSNotifierTitle,
										outString, QSNotifierText,
										@"QSCalculatorResultNotification", QSNotifierType, nil];
			QSShowNotifierWithAttributes(attributes);
			[[QSReg preferredCommandInterface] selectObject:result];
			result = nil;
		}
	}
	
	return result;
}

- (QSObject *)performCalculation:(QSObject *)dObject {
	NSString *value;
    
	if ([[dObject primaryType] isEqualToString:QSFormulaType]) {
		value = [dObject objectForType:QSFormulaType];
	} else {
		value = [dObject objectForType:QSTextType];
	}
    if ([value hasPrefix:@"="]) {
        value = [value substringFromIndex:1];        
    }
    
    NSString *outString = nil;
    
    NSString *calcEngine = [[NSUserDefaults standardUserDefaults] objectForKey:kCalculatorEngine];
    
    if ([calcEngine isEqualToString:calculatorEngineBC] || [calcEngine isEqualToString:calculatorEngineDC]) {
        value = [value stringByAppendingString:@"\n"];
        NSTask *task = [[NSTask alloc] init];
        NSPipe *inPipe = [[NSPipe alloc] init];
        NSFileHandle *input = [inPipe fileHandleForWriting];
        [task setStandardInput:inPipe];
        NSPipe *outPipe = [[NSPipe alloc] init];
        NSFileHandle *output = [outPipe fileHandleForReading];
        [task setStandardOutput:outPipe];
        [task setStandardError:outPipe];
        if ([calcEngine isEqualToString:calculatorEngineDC]) {
            [task setLaunchPath:@"/usr/bin/dc"];
        } else {
            [task setLaunchPath:@"/usr/bin/bc"];
            [task setArguments:[NSArray arrayWithObjects:@"-q",@"-l",nil]];
        }
        [task launch];
        if ([calcEngine isEqualToString:calculatorEngineDC]) {
            [input writeData:[dcStack dataUsingEncoding:NSASCIIStringEncoding allowLossyConversion:YES]];
            value = [NSString stringWithFormat:@"\n%@\n[%@\n]Pf", value, CalculatorDivider];
        }
        [input writeData:[value dataUsingEncoding:NSASCIIStringEncoding allowLossyConversion:YES]];
        [input closeFile];
        [task waitUntilExit];
        NSString *outString = nil;
        int status = [task terminationStatus];
        if (status == 0) {
            NSData *data = [output availableData];
            outString = [NSString stringWithCString:[data bytes] length:[data length]];
        } else {
            outString = @"Error";
        }
        if ([calcEngine isEqualToString:calculatorEngineDC]) {
            NSRange divRange = [outString rangeOfString:CalculatorDivider];
            if (divRange.location != NSNotFound) {
                NSString *stack = [outString substringFromIndex:(divRange.location + divRange.length)];
                stack = [[stack stringByTrimmingCharactersInSet:
                          [NSCharacterSet whitespaceAndNewlineCharacterSet]] retain];
                // Limit stack to 40 elements
                NSArray *stackArray = [stack componentsSeparatedByString:@"\n"];
                if ([stackArray count] > 40) {
                    stackArray = [stackArray subarrayWithRange:NSMakeRange(0,40)];
                    stack = [[stackArray componentsJoinedByString:@"\n"] retain];
                }
                [dcStack release];
                dcStack = [stack retain];
                outString = [outString substringToIndex:divRange.location];
            } else {
                [dcStack release];
                dcStack = [[NSString alloc] initWithString:@""];
            }
        }
        outString = [outString stringByTrimmingCharactersInSet:
                     [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        [task release];
        [inPipe release];
        [outPipe release];
            
        } else {
            
            // Source taken from QSB (BELOW) See COPYING in the Resource folder for full copyright details
            
            // Fix up separators and decimals (for current user's locale). The Calculator framework wants
            // '.' for decimals, and no grouping separators.
            NSLocale *locale = [NSLocale autoupdatingCurrentLocale];
            NSString *decimalSeparator = [locale objectForKey:NSLocaleDecimalSeparator];
            NSString *groupingSeparator
            = [locale objectForKey:NSLocaleGroupingSeparator];
            NSMutableString *fixedQuery = [NSMutableString stringWithString:value];
            [fixedQuery replaceOccurrencesOfString:groupingSeparator
                                        withString:@""
                                           options:0
                                             range:NSMakeRange(0, [fixedQuery length])];
            [fixedQuery replaceOccurrencesOfString:decimalSeparator
                                        withString:@"."
                                           options:0
                                             range:NSMakeRange(0, [fixedQuery length])];
            
            char answer[1024];
            answer[0] = '\0';
            int success
            = CalculatePerformExpression((char *)[fixedQuery UTF8String],
                                         4, 1, answer);
            if (!success) {
                // calculation failed
                return dObject;
            }
            
            outString = [NSString stringWithUTF8String:answer];
        }    
        
        QSObject *result = [QSObject objectWithName:outString];
        [result setObject:outString forType:QSTextType];
        
        return result;
    }
    
    - (BOOL)loadIconForObject:(QSObject *)object {
        
        NSString *calcEngine = [[NSUserDefaults standardUserDefaults] objectForKey:kCalculatorEngine];
        if ([calcEngine isEqualToString:calculatorEngineBC] || [calcEngine isEqualToString:calculatorEngineDC]) {
            [object setIcon:[[NSWorkspace sharedWorkspace] iconForFileType:@"'clpt'"]];
            return YES;
        }
        
        QSObject *result = [self performCalculation:object];
        
        // Still a formula object (i.e. there was a problem with the syntax) Use a clip icon
        if ([[result primaryType] isEqualToString:QSFormulaType]) {
            [object setIcon:[[NSWorkspace sharedWorkspace] iconForFileType:@"'clpt'"]];
            return YES;
        }
        // Use the result (a number) as the icon
        else {
            
            // Max icon size for the current command interface
            NSSize maxIconSize = [[QSReg preferredCommandInterface] maxIconSize];
            NSBitmapImageRep *bitmap = [[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                                                pixelsWide:maxIconSize.width
                                                                                pixelsHigh:maxIconSize.height
                                                                             bitsPerSample:8
                                                                           samplesPerPixel:4
                                                                                  hasAlpha:YES
                                                                                  isPlanar:NO
                                                                            colorSpaceName:NSCalibratedRGBColorSpace
                                                                              bitmapFormat:0
                                                                               bytesPerRow:0
                                                                              bitsPerPixel:0]
                                        autorelease];
            if(!bitmap) {
                return NO;
            }
            NSGraphicsContext *graphicsContext = [NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap];
            
            if(!graphicsContext) {
                return NO;
            }
            
            NSString *resultString = [result objectForType:QSTextType];
            
            // Set the object's details to show the result
            [object setDetails:resultString];
            
            // Sort The text format
            NSData *data = [[NSUserDefaultsController sharedUserDefaultsController] valueForKeyPath:@"values.QSAppearance1T"];
            NSColor *textColor = [NSUnarchiver unarchiveObjectWithData:data];
            
            // Text font size
            CGFloat size;
            NSSize textSize;
            NSFont *textFont;
            for (size = 12; size<300; size = size+2) {
                textFont = [NSFont boldSystemFontOfSize:size+1];
                textSize = [resultString sizeWithAttributes:[NSDictionary dictionaryWithObject:textFont forKey:NSFontAttributeName]];
                if (textSize.width> maxIconSize.width - 20 || textSize.height > maxIconSize.height - 20) {
                    break;					
                }
            }
            
            // Text shadow
            NSShadow *textShadow = [[NSShadow alloc] init];
            [textShadow setShadowOffset:NSMakeSize(5, -5)];
            [textShadow setShadowBlurRadius:10];
            [textShadow setShadowColor:[NSColor colorWithDeviceWhite:0 alpha:0.64]];
            
            NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:[NSFont boldSystemFontOfSize:size-2],NSFontAttributeName,
                                        textColor, NSForegroundColorAttributeName,
                                        textShadow, NSShadowAttributeName, nil];
            
            
            [NSGraphicsContext saveGraphicsState];
            [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap]];
            NSRect boundingRect = [[result stringValue] boundingRectWithSize:maxIconSize options:0 attributes:nil];
            [resultString drawInRect:NSMakeRect(boundingRect.origin.x+(maxIconSize.width-textSize.width)/2, boundingRect.origin.y+(maxIconSize.height-textSize.height)/2, textSize.width, textSize.height) withAttributes:attributes];
            [NSGraphicsContext restoreGraphicsState];
            NSImage *icon = [[[NSImage alloc] initWithData:[bitmap TIFFRepresentation]] autorelease];
            [object setIcon:icon];
            
            // release objects
            [textShadow release];
            
            return YES;
        }
        return NO;
    }
    
    @end