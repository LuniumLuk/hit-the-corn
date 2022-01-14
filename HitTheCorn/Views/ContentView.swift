//
//  ContentView.swift
//  HitTheCorn
//
//  Created by Ziyi Lu on 2021/6/3.
//

import SwiftUI
import RealityKit

struct ContentView : View {
    @StateObject var gameController = GameController()
    
    private let levelColors: [Color] = [Color.green, Color.yellow, Color.orange, Color.red, Color.purple]
    
    var body: some View {
        Color.black
            .ignoresSafeArea(.all) // Ignore just for the color
            .overlay(
                ZStack(alignment: .top){
                    ARGameViewContainer(gameController.arView)
                    
                    VStack {
                        Text("Score: \(gameController.score)")
                            .fontWeight(.bold)
                            .padding()
                            .font(.title)
                            .foregroundColor(Color.white)
                            .shadow(color: .black, radius: 10, x: 0.0, y: 0.0)
                        
                        HStack(alignment: .center, spacing: 20) {
                            ForEach(0..<levelColors.count) {
                                Circle()
                                    .strokeBorder(levelColors[$0], lineWidth: 5)
                                    .background(Circle().fill(Color.white))
                                    .opacity($0 > gameController.level ? 0.4 : 1.0)
                                    .frame(width: 50, height: 50)
                                    .overlay(Text("\($0 + 1)")
                                                .font(.title2)
                                                .opacity($0 > gameController.level ? 0.4 : 1.0)
                                                .foregroundColor(levelColors[$0])
                                    )
                            }
                        }
                    }
                }
            )
    }
    
    init() {
        print("View Init Called")
    }
}


#if DEBUG
struct ContentView_Previews : PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
#endif
