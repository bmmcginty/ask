# Ask

Ask is a simple tool to let you access AI providers from the command line.

## Build

`crystal build ask.cr`

## Setup

Create a file ~/.creds.yml like:
```
claude:
  api_key: "your api key goes here"
```
and a ~/.ask.yml file like:
```
default_model: "claude-3-5-sonnet-latest"
providers:
  claude: {}
```

## Run

Make a directory for each question.
Put your question, original or followup, in the question file.
Run ask.
Your question will be renumbered, and the ai's answer will be put in a sequentially numbered file ending with a.

```
mkdir weather
cd weather
echo "What is the coldest city on earth?" > question
ask
cat 02a
echo "Tell me more about the place(s) you mentioned above." > question
ask
cat 04a
```
If you find you want to toss a question/answer pair out, so the AI will not use it the next time you ask it for something, delete the file or move it into a subdirectory.
