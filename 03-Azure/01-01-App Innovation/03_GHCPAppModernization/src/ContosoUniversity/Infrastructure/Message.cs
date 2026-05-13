using System;

namespace ContosoUniversity.Infrastructure
{
    /// <summary>
    /// Represents a message for the queue system
    /// </summary>
    public class Message
    {
        public Message()
        {
            Id = Guid.NewGuid().ToString();
            Priority = MessagePriority.Normal;
            Label = string.Empty;
        }

        public Message(object body) : this()
        {
            Body = body;
        }

        public string Id { get; set; }
        public object Body { get; set; }
        public string Label { get; set; }
        public MessagePriority Priority { get; set; }
        public DateTime ArrivedTime { get; set; } = DateTime.Now;
        public TimeSpan TimeToBeReceived { get; set; } = TimeSpan.MaxValue;
    }

    /// <summary>
    /// Interface for message formatters
    /// </summary>
    public interface IMessageFormatter
    {
        object Read(Message message);
        void Write(Message message, object obj);
        bool CanRead(Message message);
    }

    /// <summary>
    /// Default message formatter
    /// </summary>
    public class DefaultMessageFormatter : IMessageFormatter
    {
        public bool CanRead(Message message)
        {
            return message?.Body != null;
        }

        public object Read(Message message)
        {
            if (message?.Body == null)
                throw new ArgumentException("Message body is null");

            return message.Body;
        }

        public void Write(Message message, object obj)
        {
            if (message == null)
                throw new ArgumentNullException(nameof(message));

            message.Body = obj;
        }
    }

    /// <summary>
    /// XML message formatter compatible with System.Messaging
    /// </summary>
    public class XmlMessageFormatter : IMessageFormatter
    {
        private readonly Type[] _targetTypes;

        public XmlMessageFormatter()
        {
            _targetTypes = new Type[] { typeof(string), typeof(object) };
        }

        public XmlMessageFormatter(Type[] targetTypes)
        {
            _targetTypes = targetTypes ?? throw new ArgumentNullException(nameof(targetTypes));
        }

        public bool CanRead(Message message)
        {
            return message?.Body != null;
        }

        public object Read(Message message)
        {
            if (message?.Body == null)
                throw new ArgumentException("Message body is null");

            // For simplicity, just return the body as-is
            // In a full implementation, you might want to deserialize XML
            return message.Body;
        }

        public void Write(Message message, object obj)
        {
            if (message == null)
                throw new ArgumentNullException(nameof(message));

            // For simplicity, just set the body
            // In a full implementation, you might want to serialize to XML
            message.Body = obj;
        }
    }
}