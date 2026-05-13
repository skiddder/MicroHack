using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;

namespace ContosoUniversity.Infrastructure
{
    /// <summary>
    /// In-memory message queue implementation that doesn't require MSMQ
    /// </summary>
    public class InMemoryMessageQueue : IMessageQueue, IDisposable
    {
        private readonly ConcurrentQueue<QueueMessage> _messages;
        private readonly object _lockObject = new object();
        private readonly string _queueName;
        private bool _disposed = false;

        public InMemoryMessageQueue(string queueName)
        {
            _queueName = queueName ?? throw new ArgumentNullException(nameof(queueName));
            _messages = new ConcurrentQueue<QueueMessage>();
        }

        public string QueueName => _queueName;

        public int Count => _messages.Count;

        public void Send(object message, string label = null, MessagePriority priority = MessagePriority.Normal)
        {
            if (_disposed)
                throw new ObjectDisposedException(nameof(InMemoryMessageQueue));

            if (message == null)
                throw new ArgumentNullException(nameof(message));

            var queueMessage = new QueueMessage
            {
                Id = Guid.NewGuid().ToString(),
                Body = message,
                Label = label ?? string.Empty,
                Priority = priority,
                CreatedAt = DateTime.Now,
                TimeToBeReceived = TimeSpan.MaxValue
            };

            _messages.Enqueue(queueMessage);
        }

        public QueueMessage Receive(TimeSpan timeout = default)
        {
            if (_disposed)
                throw new ObjectDisposedException(nameof(InMemoryMessageQueue));

            var endTime = DateTime.Now.Add(timeout == default ? TimeSpan.FromSeconds(30) : timeout);

            while (DateTime.Now < endTime)
            {
                if (_messages.TryDequeue(out var message))
                {
                    return message;
                }

                Thread.Sleep(10); // Small delay to prevent CPU spinning
            }

            throw new TimeoutException($"No message received within {timeout} timeout");
        }

        public QueueMessage Peek(TimeSpan timeout = default)
        {
            if (_disposed)
                throw new ObjectDisposedException(nameof(InMemoryMessageQueue));

            var endTime = DateTime.Now.Add(timeout == default ? TimeSpan.FromSeconds(30) : timeout);

            while (DateTime.Now < endTime)
            {
                if (_messages.TryPeek(out var message))
                {
                    return message;
                }

                Thread.Sleep(10);
            }

            throw new TimeoutException($"No message available to peek within {timeout} timeout");
        }

        public async Task<QueueMessage> ReceiveAsync(TimeSpan timeout = default, CancellationToken cancellationToken = default)
        {
            if (_disposed)
                throw new ObjectDisposedException(nameof(InMemoryMessageQueue));

            var endTime = DateTime.Now.Add(timeout == default ? TimeSpan.FromSeconds(30) : timeout);

            while (DateTime.Now < endTime && !cancellationToken.IsCancellationRequested)
            {
                if (_messages.TryDequeue(out var message))
                {
                    return message;
                }

                await Task.Delay(10, cancellationToken);
            }

            cancellationToken.ThrowIfCancellationRequested();
            throw new TimeoutException($"No message received within {timeout} timeout");
        }

        public List<QueueMessage> GetAllMessages()
        {
            if (_disposed)
                throw new ObjectDisposedException(nameof(InMemoryMessageQueue));

            return new List<QueueMessage>(_messages.ToArray());
        }

        public void Purge()
        {
            if (_disposed)
                throw new ObjectDisposedException(nameof(InMemoryMessageQueue));

            lock (_lockObject)
            {
                while (_messages.TryDequeue(out _))
                {
                    // Remove all messages
                }
            }
        }

        public void Dispose()
        {
            if (!_disposed)
            {
                Purge();
                _disposed = true;
            }
        }
    }
}