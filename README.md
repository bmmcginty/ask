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

### Quickstart

```
mkdir ai/weather
cd ai/weather
echo "Tell me about the hottest place on earth." > question
ask
cat answer
```

### Longer Example

```
mkdir ai
cd ai
mkdir weather
cd weather
echo "What is the coldest city on earth?" > question
ask
cat 02a
# same as 02a
cat answer
echo "Tell me more about the place(s) you mentioned above." > question
ask
# view new answer, linked to 04a
cat answer
# The last 4 question/answer files will no longer be sent to the AI.
ask restart
echo "Tell me how to cook pasta." > question
ask
# move that question/answer to a cooking directory
mkdir ../cooking
mv 03q 04a ../cooking/
# delete your restart file to reinclude your previous history
rm .restart
echo "Tell me even more about the above places." > question
ask
```

### Truncate History

If you start a new conversation in an existing directory, you might want to only send new messages to the AI.
You might also want to do this if you end up with a really long conversation.
Running `ask restart` will basically create a fresh start to your conversation.
Your previous questions and answers are saved, but that content won't be sent to the AI during future chats.
This restart setting is per-directory.

### Delete Content

If you find you want to toss a question/answer pair out, so the AI will not use it the next time you ask it for something, delete the file or move it into a subdirectory.

### Prompt Caching

Prompt caching is enabled by default, for cost savings purposes.
You can disable it per conversation via
`echo "" > .nocache`

### Model Selection

If you want to change the model for a conversation,
`echo "some-model-name" > .model`
