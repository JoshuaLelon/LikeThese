# Flow Diagram
```
graph LR
    Start --> Decision{Sign Up or Log In?}
    Decision --> SignUp[Create Account]
    SignUp --> OpenApp[Open App]
    Decision --> LogIn[Log In]
    LogIn --> OpenApp

    OpenApp --> InspirationsBoard[View Inspirations Board]
    InspirationsBoard --> SelectVideo[Select Video to Play]
    SelectVideo --> PlayVideo[Watch Video]
    PlayVideo --> PauseResume[Pause/Resume Playback]
    PlayVideo --> SwipeUp[Swipe Up to Replace Video]
    PlayVideo --> AutoplayNext[Autoplay Next Video]
    PlayVideo --> SwipeDown[Swipe Down to Previous Video]
    PlayVideo --> BackToGrid[Swipe Right to Return to Inspirations Board]
    BackToGrid --> InspirationsBoard
    SwipeUp --> FetchNewVideo[Fetch Replacement Video]
    FetchNewVideo --> UpdateGrid[Update Grid with New Video]

    InspirationsBoard --> Multiswipe[Multiswipe Action]
    Multiswipe --> MultiswipeIndividual[Swipe Individual Video]
    Multiswipe --> MultiswipeLeft[Swipe Left Videos]
    Multiswipe --> MultiswipeRight[Swipe Right Videos]
    Multiswipe --> MultiswipeTop[Swipe Top Videos]
    Multiswipe --> MultiswipeBottom[Swipe Bottom Videos]
    Multiswipe --> MultiswipeAll[Swipe All Videos]

    MultiswipeIndividual --> FetchNewVideo
    MultiswipeLeft --> FetchLeftVideos[Fetch New Left Videos]
    MultiswipeRight --> FetchRightVideos[Fetch New Right Videos]
    MultiswipeTop --> FetchTopVideos[Fetch New Top Videos]
    MultiswipeBottom --> FetchBottomVideos[Fetch New Bottom Videos]
    MultiswipeAll --> FetchMultipleNewVideos[Fetch All New Videos]

    FetchLeftVideos --> UpdateGrid
    FetchRightVideos --> UpdateGrid
    FetchTopVideos --> UpdateGrid
    FetchBottomVideos --> UpdateGrid
    FetchMultipleNewVideos --> UpdateGrid

    UpdateGrid --> Logout[Log Out]
    Logout --> End
```

