using System;

namespace ContosoUniversity.Infrastructure
{
    /// <summary>
    /// Compatibility layer for System.Messaging.MessageQueue
    /// This provides a drop-in replacement that doesn't require MSMQ
    /// </summary>
    public class MessageQueue : IDisposable
    {
        private readonly IMessageQueue _queue;
        private IMessageFormatter _formatter;

        public MessageQueue(string path)
        {
            if (string.IsNullOrWhiteSpace(path))
                throw new ArgumentException("Path cannot be null or empty", nameof(path));

            Path = path;
            _queue = MessageQueueManager.GetQueue(path);
            _formatter = new DefaultMessageFormatter();
        }

        public string Path { get; private set; }

        public IMessageFormatter Formatter
        {
            get => _formatter;
            set => _formatter = value ?? throw new ArgumentNullException(nameof(value));
        }

        /// <summary>
        /// Creates a new queue
        /// </summary>
        public static MessageQueue Create(string path, bool transactional = false)
        {
            if (string.IsNullOrWhiteSpace(path))
                throw new ArgumentException("Path cannot be null or empty", nameof(path));

            MessageQueueManager.Create(path, transactional);
            return new MessageQueue(path);
        }

        /// <summary>
        /// Checks if queue exists
        /// </summary>
        public static bool Exists(string path)
        {
            return MessageQueueManager.Exists(path);
        }

        /// <summary>
        /// Deletes a queue
        /// </summary>
        public static void Delete(string path)
        {
            MessageQueueManager.Delete(path);
        }

        /// <summary>
        /// Sends a message to the queue
        /// </summary>
        public void Send(object obj, string label = null)
        {
            if (obj == null)
                throw new ArgumentNullException(nameof(obj));

            if (obj is Message message)
            {
                _queue.Send(message, message.Label ?? label);
            }
            else
            {
                var formattedMessage = new Message(obj)
                {
                    Label = label ?? string.Empty
                };
                _queue.Send(formattedMessage, label);
            }
        }

        /// <summary>
        /// Receives a message from the queue
        /// </summary>
        public Message Receive()
        {
            return Receive(TimeSpan.FromSeconds(30));
        }

        /// <summary>
        /// Receives a message from the queue with timeout
        /// </summary>
        public Message Receive(TimeSpan timeout)
        {
            var queueMessage = _queue.Receive(timeout);
            
            if (queueMessage.Body is Message message)
            {
                return message;
            }

            // Convert back to Message format
            return new Message(queueMessage.Body)
            {
                Label = queueMessage.Label
            };
        }

        /// <summary>
        /// Peeks at the next message without removing it
        /// </summary>
        public Message Peek()
        {
            return Peek(TimeSpan.FromSeconds(30));
        }

        /// <summary>
        /// Peeks at the next message with timeout
        /// </summary>
        public Message Peek(TimeSpan timeout)
        {
            var queueMessage = _queue.Peek(timeout);
            
            if (queueMessage.Body is Message message)
            {
                return message;
            }

            return new Message(queueMessage.Body)
            {
                Label = queueMessage.Label
            };
        }

        /// <summary>
        /// Purges all messages from the queue
        /// </summary>
        public void Purge()
        {
            _queue.Purge();
        }

        /// <summary>
        /// Sets permissions (no-op for in-memory implementation)
        /// </summary>
        public void SetPermissions(string user, object rights)
        {
            // No-op for in-memory implementation
            // In a real scenario, you might want to implement some form of access control
        }

        public void Dispose()
        {
            // Queue is managed by MessageQueueManager, so we don't dispose it here
        }
    }
}