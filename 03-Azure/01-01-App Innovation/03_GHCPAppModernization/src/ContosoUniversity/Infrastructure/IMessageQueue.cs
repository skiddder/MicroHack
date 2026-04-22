using System;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;

namespace ContosoUniversity.Infrastructure
{
    /// <summary>
    /// Interface for message queue operations
    /// </summary>
    public interface IMessageQueue
    {
        string QueueName { get; }
        int Count { get; }
        
        void Send(object message, string label = null, MessagePriority priority = MessagePriority.Normal);
        QueueMessage Receive(TimeSpan timeout = default);
        QueueMessage Peek(TimeSpan timeout = default);
        Task<QueueMessage> ReceiveAsync(TimeSpan timeout = default, CancellationToken cancellationToken = default);
        List<QueueMessage> GetAllMessages();
        void Purge();
    }

    /// <summary>
    /// Represents a message in the queue
    /// </summary>
    public class QueueMessage
    {
        public string Id { get; set; }
        public object Body { get; set; }
        public string Label { get; set; }
        public MessagePriority Priority { get; set; }
        public DateTime CreatedAt { get; set; }
        public TimeSpan TimeToBeReceived { get; set; }
    }

    /// <summary>
    /// Message priority levels
    /// </summary>
    public enum MessagePriority
    {
        Lowest = 0,
        VeryLow = 1,
        Low = 2,
        Normal = 3,
        AboveNormal = 4,
        High = 5,
        VeryHigh = 6,
        Highest = 7
    }
}