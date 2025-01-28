# Ask

Ask is a simple tool to let you access AI providers from the command line.

## Build

`crystal build ask.cr`

## Setup

By default, ask uses Anthropic's Claud AI.
I'm happy to add providers; open an issue, prefforably with a link to the api doc for the AI in question.

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

Make a directory for each conversation.
Put your question, original or followup, in the question file.
Run `ask`.
Your question will be put in a sequentially numbered file ending with `q`,
and the AI's answer will be put in a sequentially numbered file ending with `a`.
Each new answer will also be linked to `answer`, so long as answer does not exist, or is a symlink.

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

### Delete Content

If you find you want to toss a question/answer pair out, so the AI will not use it the next time you ask it for something, delete the file or move it into a subdirectory.

### Prompt Caching

Prompt caching is enabled by default, for cost savings purposes.
You can disable it per conversation via
`echo "" > .nocache`

### Model Selection

If you want to change the model for a conversation,
`echo "some-model-name" > .model`
