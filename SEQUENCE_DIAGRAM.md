## Sequence Diagram
```
sequenceDiagram
    participant User
    participant App
    participant FirebaseAuth
    participant Firestore
    participant Storage

    User->>App: Launch app
    App->>User: Show "Sign Up" or "Log In" screen

    alt Create Account
        User->>App: Sign Up
        App->>FirebaseAuth: Submit user signup credentials
        FirebaseAuth-->>App: Return session token
        App->>User: Account created and session active
    end

    alt Log In
        User->>App: Log In
        App->>FirebaseAuth: Submit user login credentials
        FirebaseAuth-->>App: Return session token
        App->>User: Session active (successful login)
    end

    User->>App: View Inspirations Board
    App->>Firestore: Fetch Inspirations grid videos
    Firestore-->>App: Return video recommendations

    User->>App: Tap video to play
    App->>Storage: Stream video from Firebase Storage
    User->>App: Tap to pause/play
    User->>App: Swipe up to replace video
    App->>Firestore: Request new video recommendation
    Firestore-->>App: Return new video
    App->>User: Display new video in grid
    User->>App: Swipe down to revisit previous video
    App->>Firestore: Fetch previous video
    Firestore-->>App: Return previous video
    App->>User: Display previous video
    User->>App: Swipe right to return to Inspirations board
    App->>User: Display Inspirations grid

    User->>App: Multiswipe action
    App->>Firestore: Fetch multiple new recommendations
    Firestore-->>App: Return multiple new videos
    App->>User: Update grid with new videos

    User->>App: Log Out
    App->>FirebaseAuth: End session token
    FirebaseAuth-->>App: Confirm logout
    App->>User: Return to launch or sign-in screen
```