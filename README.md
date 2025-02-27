# Showdown_Realtime

A Ruby on Rails application that plays Pokemon Showdown and streams on Twitch with AI-powered commentary. _This summary was generated with Claude 3.7_.

## Overview

Showdown_Realtime is a real-time AI-powered streaming system that plays Pokemon Showdown battles on Twitch. The application uses OpenAI's services for both voice commentary and gameplay decision-making based on Twitch chat input. Currently live at [twitch.tv/adetna](https://twitch.tv/adetna).

This project was built as a technical demonstration for the Ruby AI community, showcasing how Ruby on Rails can be used to build complex real-time AI-powered applications.

## Key Features

- **Live 24/7 AI-Powered Gameplay**: Continuously plays Pokemon Showdown battles
- **Twitch Chat Integration**: Viewers can suggest moves that the AI will consider
- **Real-Time Voice Commentary**: AI-generated commentary on battle events
- **Automated Battle Flow**: Handles game state, move selection, and battle transitions

## Technical Architecture

The application consists of several interconnected services:

- **Pokemon Showdown Interface**: Connects to the Pokemon Showdown websocket API to send commands and receive battle state
- **OpenAI Function Service**: Processes Twitch chat and battle state to make gameplay decisions
- **OpenAI Voice Service**: Generates audio commentary based on battle events
- **Twitch Service**: Handles Twitch chat integration via IRC
- **OBS Service**: Controls stream state (pausing/resuming)
- **RTMP Server**: Routes audio to the streaming service

All services communicate through async queues to maintain real-time operation within the 15-second move time limit.

## Technologies Used

- **Ruby on Rails**: Core application framework
- **Async Ruby**: For handling multiple real-time websocket connections
- **OpenAI API**: For voice generation and function calling
- **Twitch API**: For chat integration
- **OBS Websocket**: For stream control
- **FFmpeg**: For audio processing

## Challenges & Solutions

- **Real-time Constraints**: Operating within Pokemon Showdown's 15-second turn limit
- **Audio Buffering**: Managing the fact that OpenAI returns audio faster than real-time
- **Streaming Lag**: Optimized for minimum delay (currently ~6 seconds when I stream from Florida)
- **State Management**: Coordinating multiple stateful websocket connections
- **Service Communication**: Using async queues for inter-service messaging

## Future Development

- **Avatar Integration**: Adding a visual component/VTuber style representation
- **Additional Games**: Working on Pokemon Fire Red/Leaf Green integration
- **Improved Chat Interaction**: Enhanced AI responses to chat messages
- **Multi-Service Architecture**: Breaking the monolithic structure into separate processes

## Resources

- [Presentation](https://docs.google.com/presentation/d/19kXxKmUKc65gO6DZ1HuJn2Vm4A6e0olFDIFlGTfkT_Q/edit?usp=drive_link)
- [Architecture Documentation](https://docs.google.com/document/d/14_2yKqeLsZEtPfuY4qt3Fo534bHlPU1cIFqEKCcR5L0/edit?usp=drive_link)
- [Recorded Talk](https://drive.google.com/file/d/1ZLObiQx5Rp_Kj6UmDgoQGnryBpznrUiI/view?usp=drive_link)

## Contact

Created by [Andrew Denta](https://linkedin.com/in/adenta). Feel free to reach out with questions about the project.
