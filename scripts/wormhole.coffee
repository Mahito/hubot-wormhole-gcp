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
  Datastore = require('@google-cloud/datastore')
  projectId = process.env.HUBOT_GCP_PROJECT_ID
  keyFilename = process.env.GOOGLE_APPLICATION_CREDENTIALS

  pubsubClient = new PubSub({
      projectId: projectId,
      keyFilename: keyFilename,
  })
  datastore = new Datastore({
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

      robot.adapter.client.web.channels.info(res.message.room)
        .then((response) ->
          payload = {
                    action: "post",
                    posted: res.message.rawMessage.ts,
                    icon_url: icon,
                    username: username,
                    text: res.message.text,
                    as_user: false,
                    room: response.channel.name
                  }

          topic.publisher()
               .publish(Buffer.from(JSON.stringify(payload)))
               .catch((err) ->
                  res.send('ERROR:', err)
                )
        )

    message_changed = (event) ->
      topicName = process.env.HUBOT_WORMHOLE_TOPIC_NAME
      topic = pubsubClient.topic(topicName)

      robot.adapter.client.web.channels.info(event.channel.id)
        .then((res) ->
          room = res.channel.name
          payload = {
                      action: "update",
                      posted: event.message.ts,
                      text: event.message.text,
                    }

          topic.publisher()
               .publish(Buffer.from(JSON.stringify(payload)))
               .catch((err) ->
                 robot.send {room: room}, {text: err};
               )
        )
        .catch((err) ->
          robot.send {room: event.channel.id}, {text: err};
        )

    message_deleted = (event) ->
      topicName = process.env.HUBOT_WORMHOLE_TOPIC_NAME
      topic = pubsubClient.topic(topicName)

      robot.adapter.client.web.channels.info(event.channel.id)
        .then((res) ->
          room = res.channel.name
          payload = {
                      action: "delete",
                      posted: event.previous_message.ts,
                    }

          topic.publisher()
               .publish(Buffer.from(JSON.stringify(payload)))
               .catch((err) ->
                 robot.send {room: room}, {text: err};
               )
        )
        .catch((err) ->
          robot.send {room: event.channel.id}, {text: err};
        )


    robot.adapter.client.rtm.on 'message', (event) ->
      if event.type is 'message'
        if event.subtype isnt 'message_changed' and event.subtype isnt 'message_deleted'
          return

        if event.subtype is 'message_changed'
          message_changed(event)

        if event.subtype is 'message_deleted'
          message_deleted(event)

    if isOut == 'yes'
      subscriptionName = process.env.HUBOT_WORMHOLE_SUBSCRIPTION_NAME
      subscription = pubsubClient.subscription(subscriptionName)

      messageHandler = (message) ->
        payload = JSON.parse(message.data)

        if payload['action'] == 'post'
          room = payload['room']
          robot.adapter.client.web.chat.postMessage(room, payload['text'], payload)
            .then((res) ->
              datastoreKey = datastore.key(['wormhole'])
              data = {
                originalTs: payload['posted'],
                timestamp: res.message.ts,
                channelID: res.channel
              }
              entity = { key: datastoreKey, data: data }

              datastore.save(entity)
                .then(() -> )
                .catch((err) ->
                  robot.send {room: room}, {text: err}
                )
          )

        else if payload['action'] == 'update'
          query = datastore.createQuery('wormhole')
                           .filter('originalTs', '=', payload['posted'])
                           .limit(1)

          datastore.runQuery(query)
            .then((result) ->
              data = result[0]
              data.forEach((d) ->
                robot.adapter.client.web.chat.update(d.timestamp, d.channelID, payload['text'])
                  .then(() ->)
              )
            )

        else if payload['action'] == 'delete'
          query = datastore.createQuery('wormhole')
                           .filter('originalTs', '=', payload['posted'])
                           .limit(1)

          datastore.runQuery(query)
            .then((result) ->
              data = result[0]
              data.forEach((d) ->
                robot.adapter.client.web.chat.delete(d.timestamp, d.channelID)
                  .then(() ->
                    datastoreKey = datastore.key(['wormhole', Number(d[datastore.KEY].id)])
                    datastore.delete(datastoreKey)
                    .then(() -> )
                  )
              )
            )

        message.ack()

      subscription.on('message', messageHandler)
