//
//  ContentView.swift
//  PushEngageNotificationContentExtenstion
//
//  Created by Abhishek on 28/04/21.
//

import SwiftUI
import PushEngage

// swiftlint:disable all

@available(iOSApplicationExtension 13.0, *)
struct ContentView: View {
    
    var payLoadInfo: CustomUIModel
    
    var body: some View {
        VStack(alignment: .center,spacing: 10) {
            HStack(alignment: .center) {
                Text("PushEngage Notification")
                    .foregroundColor(.black)
                    .bold()
                Image("image")
                    .resizable()
                    .padding()
                    .frame(width: 20, height: 20, alignment: /*@START_MENU_TOKEN@*/.center/*@END_MENU_TOKEN@*/)
            }
            Image(uiImage: payLoadInfo.image ?? UIImage())
                .resizable()
                .frame(width: 300, height: 300,
                       alignment: /*@START_MENU_TOKEN@*/.center/*@END_MENU_TOKEN@*/)
            Text(payLoadInfo.title)
                .foregroundColor(.black)
                .fontWeight(.medium)
                .padding(.all, 10)
            Text(payLoadInfo.body)
                .foregroundColor(.black)
                .fontWeight(.regular)
                .padding(.all, 10)
            HStack(alignment: .center, spacing: 40) {
                buttonShow
            }
        }.background(Color.white)
    }
    
    @ViewBuilder
    private var buttonShow: some View {
        if let buttons = payLoadInfo.buttons {
            ForEach(buttons, id: \.id) { button in
                ActionButton(button: button)
            }
        }
    }
}

@available(iOSApplicationExtension 13.0, *)
struct ActionButton: View {
    
    var button: CustomUIButtons
    
    var body: some View {
        Button(button.text) {
            print(button.id)
        }
        .id(button.id)
        .foregroundColor(.white)
        .background(Color.blue)
        .border(Color.white, width: 0.2)
        .padding(.bottom , 10)
        .cornerRadius(3.0)
    }
}

