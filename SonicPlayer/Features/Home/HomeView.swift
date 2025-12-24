import ComposableArchitecture
import SwiftUI

struct HomeView: View {
    @Bindable var store: StoreOf<HomeFeature>
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // 1. Playing Now / Keep Listening
                    if let lastTrack = store.lastPlayedTrack, lastTrack.duration > 0  {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Playing Now")
                                .font(.title2)
                                .fontWeight(.bold)
                                .padding(.horizontal)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(alignment: .top, spacing: 16) {
                                    UpNextCard(
                                        track: lastTrack,
                                        isPlaying: store.isPlaying,
                                        progress: store.playbackProgress,
                                        artwork: store.artworkCache[lastTrack.url],
                                        colors: store.colorCache[lastTrack.url] ?? Color.sonicTealColors,
                                        action: {
                                            store.send(.playTrack(lastTrack))
                                        },
                                        onAppear: {
                                            store.send(.loadArtwork(lastTrack.url, isFolder: false))
                                        },
                                        width: 160,
                                        fallbackColors: Color.sonicTealColors
                                    )
                                }
                                .padding(.leading)
                                .padding(.trailing)
                            }
                        }
                    }
                    
                    // 2. You Might Like / Shows For You
                    if !store.suggestedFolders.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("You Might Like")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                Spacer()
                                Button("See All") {
                                    store.send(.libraryTapped)
                                }
                                .font(.subheadline)
                            }
                            .padding(.horizontal)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(alignment: .top, spacing: 16) {
                                    ForEach(store.suggestedFolders) { folder in
                                        FolderCard(
                                            folder: folder,
                                            artwork: store.artworkCache[folder.url],
                                            colors: store.colorCache[folder.url] ?? Color.sonicPurpleColors,
                                            onAppear: {
                                                store.send(.loadArtwork(folder.url, isFolder: true))
                                            },
                                            width: 160,
                                            fallbackColors: Color.sonicPurpleColors
                                        )
                                        .onTapGesture {
                                            store.send(.folderTapped(folder))
                                        }
                                    }
                                }
                                .padding(.leading)
                                .padding(.trailing)
                            }
                        }
                    }
                    
                    // 3. Recent Folders
                    if !store.recentFolders.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Recent Adds")
                                .font(.title2)
                                .fontWeight(.bold)
                                .padding(.horizontal)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(alignment: .top, spacing: 16) {
                                    ForEach(store.recentFolders) { folder in
                                        FolderCard(
                                            folder: folder,
                                            artwork: store.artworkCache[folder.url],
                                            colors: store.colorCache[folder.url] ?? Color.sonicOrangeColors,
                                            onAppear: {
                                                store.send(.loadArtwork(folder.url, isFolder: true))
                                            },
                                            width: 160,
                                            fallbackColors: Color.sonicOrangeColors
                                        )
                                        .onTapGesture {
                                            store.send(.folderTapped(folder))
                                        }
                                    }
                                }
                                .padding(.leading)
                                .padding(.trailing)
                            }
                        }
                    }
                    
                    // 4. Explore / Library
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Explore")
                            .font(.title2)
                            .fontWeight(.bold)
                            .padding(.horizontal)
                        
                        Button {
                            store.send(.libraryTapped)
                        } label: {
                            HStack {
                                Image(systemName: "square.stack.3d.up.fill")
                                    .font(.title)
                                    .foregroundColor(.white)
                                    .frame(width: 50, height: 50)
                                    .background(LinearGradient.sonicGradientBlue)
                                    .cornerRadius(12)
                                
                                VStack(alignment: .leading) {
                                    Text("Library")
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    Text("All your files and folders")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical)
                .padding(.bottom, 80) // Add bottom padding for Mini Player
            }
            .navigationTitle("Home")
            .navigationBarTitleDisplayMode(.large)
            .background(Color.sonicBackground.ignoresSafeArea())
            .onAppear {
                store.send(.onAppear)
            }
        }
    }
}

// MARK: - Components

struct UpNextCard: View {
    let track: AudioFile
    let isPlaying: Bool
    let progress: Double // 0.0 to 1.0
    let artwork: UIImage?
    let colors: [Color]
    let action: () -> Void
    let onAppear: () -> Void
    var width: CGFloat = 160
    var fallbackColors: [Color]? = nil

    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                // Artwork with Progress Bar
                ZStack(alignment: .bottom) {
                    if let artwork {
                        Image(uiImage: artwork)
                            .resizable()
                            .scaledToFill()
                            .frame(width: width)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(
                                        LinearGradient(
                                            colors: [.clear, .black.opacity(0.5)],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                                    .overlay {
                                        waveframeOverlay
                                    }
                            }
                            .overlay {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.sonicPrimaryLight.opacity(0.15))
                                    .frame(width: width, height: 220)
                            }
                    } else {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(
                                LinearGradient(
                                    colors: artwork != nil ? colors : Color.sonicTealColors,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .overlay(alignment: .center) {
                                waveframeOverlay
                            }
                    }
                    
                    // Play/Pause Button
                    HStack {
                        Spacer()
                        VStack {
                            Spacer()
                            Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 32))
                                .foregroundColor(.white)
                                .shadow(color: .black.opacity(0.4), radius: 6, x: 0, y: 2)
                                .padding(12)
                        }
                    }

                    // Waveform Progress Bar
                   

                    // Border overlay
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            LinearGradient(
                                colors: [.white.opacity(0.4), .white.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                }
                .shadow(color: colors.first?.opacity(0.4) ?? .sonicPrimary.opacity(0.3), radius: 12, x: 0, y: 6)
                .scaleEffect(isPressed ? 0.95 : 1.0)
                .frame(width: width, height: 220)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)

                // Text Details
                VStack(alignment: .leading, spacing: 4) {
                    Text("CONTINUE LISTENING")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(
                            LinearGradient(
                                colors: colors.isEmpty ? Color.sonicTealColors : colors,
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )

                    Text(track.title)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.caption2)
                        Text(track.durationFormatted)
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: .infinity, maximumDistance: .infinity, pressing: { pressing in
            isPressed = pressing
        }, perform: {})
        .onAppear {
            onAppear()
        }
    }
    
    private var waveframeOverlay: some View {
        VStack {
            GeometryReader { geo in
                HStack(spacing: 0) {
                    // Played Segment (Brighter)
                    Color.white.opacity(0.9)
                        .frame(width: geo.size.width * progress)
                    
                    // Unplayed Segment (Dimmer Background)
                    Color.white.opacity(0.3)
                        .frame(width: geo.size.width * (1 - progress))
                }
                .mask {
                    WaveformView(
                        isPlaying: isPlaying,
                        barCount: 16,      // Enough bars to fill width
                        barWidth: 4,       // Thicker bars
                        baseHeight: 32,    // Taller base
                        amplitudeRange: 4...34 // More visible animation
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped() // Ensure waveform is clipped
                }
            }
            .frame(maxHeight: .infinity)
            .padding(0)
            .padding(.vertical, 12)
            
        }
    }
}

