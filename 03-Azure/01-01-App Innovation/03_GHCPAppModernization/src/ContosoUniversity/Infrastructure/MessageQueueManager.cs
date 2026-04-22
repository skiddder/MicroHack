using System;
using System.Collections.Concurrent;
using System.Collections.Generic;

namespace ContosoUniversity.Infrastructure
{
    /// <summary>
    /// Static manager for in-memory message queues
    /// </summary>
    public static class MessageQueueManager
    {
        private static readonly ConcurrentDictionary<string, IMessageQueue> _queues = 
            new ConcurrentDictionary<string, IMessageQueue>();

        /// <summary>
        /// Creates or gets an existing queue
        /// </summary>
        public static IMessageQueue Create(string queuePath, bool transactional = false)
        {
            if (string.IsNullOrWhiteSpace(queuePath))
                throw new ArgumentException("Queue path cannot be null or empty", nameof(queuePath));

            // Normalize queue path (remove .\ prefix and convert to simple name)
            var normalizedPath = NormalizeQueuePath(queuePath);

            return _queues.GetOrAdd(normalizedPath, path => new InMemoryMessageQueue(path));
        }

        /// <summary>
        /// Gets an existing queue
        /// </summary>
        public static IMessageQueue GetQueue(string queuePath)
        {
            var normalizedPath = NormalizeQueuePath(queuePath);
            
            if (_queues.TryGetValue(normalizedPath, out var queue))
            {
                return queue;
            }

            throw new InvalidOperationException($"Queue '{queuePath}' does not exist. Use Create() method first.");
        }

        /// <summary>
        /// Checks if a queue exists
        /// </summary>
        public static bool Exists(string queuePath)
        {
            var normalizedPath = NormalizeQueuePath(queuePath);
            return _queues.ContainsKey(normalizedPath);
        }

        /// <summary>
        /// Deletes a queue
        /// </summary>
        public static void Delete(string queuePath)
        {
            var normalizedPath = NormalizeQueuePath(queuePath);
            
            if (_queues.TryRemove(normalizedPath, out var queue))
            {
                if (queue is IDisposable disposableQueue)
                {
                    disposableQueue.Dispose();
                }
            }
        }

        /// <summary>
        /// Gets all queue names
        /// </summary>
        public static IEnumerable<string> GetAllQueueNames()
        {
            return _queues.Keys;
        }

        /// <summary>
        /// Clears all queues
        /// </summary>
        public static void ClearAll()
        {
            foreach (var queue in _queues.Values)
            {
                if (queue is IDisposable disposableQueue)
                {
                    disposableQueue.Dispose();
                }
            }
            _queues.Clear();
        }

        private static string NormalizeQueuePath(string queuePath)
        {
            if (string.IsNullOrWhiteSpace(queuePath))
                return queuePath;

            // Handle common MSMQ path formats
            var path = queuePath.Trim();
            
            // Remove .\ prefix
            if (path.StartsWith(".\\"))
                path = path.Substring(2);

            // Handle Private$ format
            if (path.StartsWith("Private$\\"))
                path = path.Substring(9);

            return path;
        }
    }
}