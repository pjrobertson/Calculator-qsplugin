//
//  CalculatorAction.h
//  Quicksilver
//
// Created by Kevin Ballard, modified by Patrick Robertson
// Copyright QSApp.com 2011

#define CalculatorCalculateAction @"CalculatorCalculateAction"
#define kCalculatorEngine @"CalculatorEngine"

@interface CalculatorActionProvider : QSActionProvider {
    NSString *dcStack;
}

- (QSObject *)calculate:(QSObject *)dObject;
- (QSObject *)performCalculation:(QSObject *)dObject;

@end
