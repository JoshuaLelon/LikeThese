# Flow Diagram
Note: All previous references to `thumbnailUrl` have been updated to use `frameUrl` for consistency with the new hybrid approach.
```
graph LR
    Start --> AuthChoice{Sign Up or Log In}
    AuthChoice --> SignUp[Create Account]
    SignUp --> OpenApp[Open App]
    AuthChoice --> LogIn[Log In]
    LogIn --> OpenApp

    OpenApp --> InspirationsBoard[View Inspirations Board]
    InspirationsBoard --> SelectVideo[Tap a thumbnail to watch fullscreen]
    SelectVideo --> PlayingVideo[Playing a video from board or random]

    PlayingVideo --> PauseResume[Tap to pause/resume]
    PlayingVideo --> SwipeDown[Swipe down to previous video]
    PlayingVideo --> BackToGrid[Swipe right, return to board]
    PlayingVideo --> AutoplayNext[Autoplay next video]
    PlayingVideo --> SwipeUpFromPlayer[Swipe up → random next]
    AutoplayNext --> PlayingVideo
    SwipeUpFromPlayer --> PlayingVideo

    InspirationsBoard --> SingleSwipe[Swipe up on a thumbnail]
    SingleSwipe --> CandidateFlow[Compute least similar via Replicate & LangSmith]
    CandidateFlow --> ExtractFrames[Extract frames]
    ExtractFrames --> ComputeEmbeddings[Compute CLIP embeddings]
    ComputeEmbeddings --> CompareEmbeddings[Compare to board]
    CompareEmbeddings --> PickLeastSimilar[Highest distance → least similar]
    PickLeastSimilar --> GeneratePosterImage[Generate poster image]
    PickLeastSimilar --> LogRun[Log run in LangSmith]
    GeneratePosterImage --> LogRun
    LogRun --> ReturnVideoID[Return chosen video ID]
    ReturnVideoID --> UpdateGrid[Update board with new video]
    UpdateGrid --> InspirationsBoard

    InspirationsBoard --> Logout[Log out]
    Logout --> End
```


---

## Known Mermaid Diagram Errors and Fixes

Below is a summary of the parse errors we ran into during this conversation, along with their root causes and how we fixed them.

### 1) Error: "Parse error on line…" involving parentheses or quotes in node labels

> **Example Snippet (Trigger)**  
> ```
> CompareEmbeddings[Compare vs. Board Embeddings
> (Replicate CLIP Model)]
> ```
> **Error**:  
> ```
> Diagram syntax error
> Expecting 'SQE' ... got 'PS'
> ```
>  
> **Root Cause**  
> Mermaid sometimes chokes on unescaped parentheses or quotes directly in node labels.  
>  
> **Fix**  
> We removed or escaped parentheses and used simpler labels, e.g.:  
> ```
> CompareEmbeddings[Compare vs board with cosine distance]
> ```
>  
> **What Led to the Fix**  
> After repeated errors, we realized removing parentheses/quotes or escaping them (`\( \)`) resolves the parse issue.

---

### 2) Error: "Parse error on line…" involving curly quotes or special characters

> **Example Snippet (Trigger)**  
> ```
> CandidateFlow((Compute "Least Similar"
> via Replicate
> +Optional LangSmith))
> ```
> **Error**:  
> ```
> Diagram syntax error
> Expecting ... got 'STR'
> ```
>  
> **Root Cause**  
> Curly quotes (") or multi-line strings in a Mermaid label cause parse issues.  
>  
> **Fix**  
> Replace curly quotes with straight quotes or remove quotes entirely. Also avoid abrupt line breaks.  
>  
> **What Led to the Fix**  
> We systematically removed curly quotes and restricted multiline text to `<br/>` or shorter single-line labels.

---

### 3) Error: "Parse error on line…" when using code fences and markdown simultaneously

> **Example Snippet (Trigger)**  
> ```
> ```mermaid
> graph LR
> ...
> ```
> ```
> (Nested code blocks can break rendering in some contexts.)
>  
> **Root Cause**  
> Nested triple-backtick blocks can confuse the parser if not well-formed in Markdown.  
>  
> **Fix**  
> We ensured we had properly opened and closed code fences once, and used a single ` ```mermaid ` or ` ``` ` block.  
>  
> **What Led to the Fix**  
> Observing that removing nested triple backticks eliminated parse breaks.

---

### 4) Error: "Parse error" whenever special punctuation or partial lines remained

> **Example Snippet (Trigger)**  
> ```
> text # "Compute 'least similar' ...
> Autoplay Next Video (Random)"
> ```
> **Root Cause**  
> If punctuation like `(`, `'`, or `"` is placed in a node label incorrectly, Mermaid's parser fails.  
>  
> **Fix**  
> We replaced or removed parentheses and quotes, or used `\(` and `\)` as escapes where needed.  
>  
> **What Led to the Fix**  
> Ongoing trial and error showed that removing or escaping these characters in node labels allowed successful parsing.

---

## Summary

1. **List of errors**: All centered on Mermaid parse errors.  
2. **Root causes**: Unescaped parentheses, curly quotes, special punctuation, or multiline labels.  
3. **Fix approach**: Remove or escape problematic characters, simplify labels, avoid nested code blocks or curly quotes.  
4. **Explanation**: By limiting node labels to plain text without parentheses/curly quotes, or by properly escaping them, we resolved the parsing issues.

That covers all the errors we encountered, why they happened, and how we fixed them.