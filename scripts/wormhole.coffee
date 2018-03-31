# Description:
#   Script to inhale the message on any channels and
#   exhale it to a specific channel in another Workspace
#
# Notes:
#   They are commented out by default, because most of them are pretty silly and
#   wouldn't be useful and amusing enough for day to day huboting.
#   Uncomment the ones you want to try and experiment with.
#
#   These are from the scripting documentation: https://github.com/github/hubot/blob/master/docs/scripting.md

module.exports = (robot) ->
  isIn  = process.env.HUBOT_WORMHOLE_IN
  isOut = process.env.HUBOT_WORMHOLE_OUT

  PubSub = require('@google-cloud/pubsub')
  projectId = process.env.HUBOT_GCP_PROJECT_ID
  keyFilename = process.env.GOOGLE_APPLICATION_CREDENTIALS

  pubsubClient = new PubSub({
      projectId: projectId,
      keyFilename: keyFilename,
  })

  if isIn == 'yes'
    robot.hear /.*/i, (res) ->
      topicName = process.env.HUBOT_WORMHOLE_TOPIC_NAME
      topic = pubsubClient.topic(topicName)

      username = res.message.user.profile.display_name ||
                 res.message.user.profile.real_name ||
                 res.message.user.name
      icon = res.message.user.profile.image_192

      robot.adapter.client.web.conversations.info(res.message.room)
        .then((response) ->
          room = response.channel.name
          payload = { username: username, icon_url: icon, text: res.message.rawText, as_user: false, room: room }
          topic.publisher()
               .publish(Buffer.from(JSON.stringify(payload)))
               .catch((err) ->
                  res.send('ERROR:', err)
                )
          )


    if isOut == 'yes'
      subscriptionName = process.env.HUBOT_WORMHOLE_SUBSCRIPTION_NAME
      subscription = pubsubClient.subscription(subscriptionName)

      messageHandler = (message) ->
        send = (room, msg) -> robot.send {room: room}, msg
        payload = JSON.parse(message.data)
        send(payload['room'], payload)
        message.ack()

      subscription.on('message', messageHandler)
