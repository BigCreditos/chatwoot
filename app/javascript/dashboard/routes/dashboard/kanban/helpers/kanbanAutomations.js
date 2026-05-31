/* eslint-disable no-console, no-unused-vars, no-restricted-syntax, no-continue, no-await-in-loop */
import { KanbanConfigHelper } from './kanbanConfig';

export const KanbanAutomations = {
  /**
   * Registers a store subscriber to run active pipeline automations
   * @param {Object} store - The Vuex store instance
   * @returns {Function} Unsubscribe handler function
   */
  register(store) {
    let config = null;

    // Load active config on registration
    const reloadConfig = async () => {
      try {
        const result = await KanbanConfigHelper.loadConfig(store);
        config = result.config;
      } catch (err) {
        console.error('Failed to load Kanban config for automations:', err);
      }
    };

    reloadConfig();

    // Helper: assign a conversation to the first stage of a matching pipeline
    const tryAutoCreate = async conversation => {
      if (!conversation || !conversation.id) return;
      if (!config || !Array.isArray(config.pipelines)) return;

      for (const pipeline of config.pipelines) {
        if (!pipeline.automations?.auto_create) continue;

        const inboxFilter = pipeline.inboxes || [];
        if (
          inboxFilter.length > 0 &&
          !inboxFilter.includes(conversation.inbox_id)
        ) {
          continue;
        }

        const stageLabels = pipeline.stages.map(s => s.label);
        const hasStageLabel = conversation.labels?.some(lbl =>
          stageLabels.includes(lbl)
        );

        if (!hasStageLabel && pipeline.stages.length > 0) {
          const firstStage = pipeline.stages[0];
          const currentLabels = [...(conversation.labels || [])];
          currentLabels.push(firstStage.label);

          try {
            await store.dispatch('conversationLabels/update', {
              conversationId: conversation.id,
              labels: currentLabels,
            });
            // Sync updated labels back to conversations store
            store.dispatch('updateConversation', {
              id: conversation.id,
              labels: currentLabels,
            });
          } catch (err) {
            console.error(
              `Automation failed: auto_create for chat #${conversation.id}`,
              err
            );
          }
        }
      }
    };

    // Subscribe to store mutations
    return store.subscribe(async (mutation, state) => {
      const { type, payload } = mutation;

      // 1. New Conversation Created/Received Automation
      if (type === 'ADD_CONVERSATION') {
        const conversation = payload;
        if (!conversation || !conversation.id) return;

        // Skip if config is not loaded yet
        if (!config || !Array.isArray(config.pipelines)) return;

        // Skip conversations that start resolved (native Chatwoot campaigns)
        if (conversation.status === 'resolved') return;

        // Skip if the conversation was initiated by the agent (outbound message)
        const firstMsg =
          conversation.last_non_activity_message || conversation.messages?.[0];
        if (firstMsg && firstMsg.message_type === 1) return;

        await tryAutoCreate(conversation);
      }

      // 2. Update: customer replied to an existing conversation not yet in pipeline
      if (type === 'UPDATE_CONVERSATION') {
        const conversation = payload;
        if (!conversation || !conversation.id) return;
        if (!config || !Array.isArray(config.pipelines)) return;
        if (conversation.status !== 'open') return;

        // Skip if already in any pipeline
        const alreadyInPipeline = config.pipelines.some(p =>
          p.stages.some(s => conversation.labels?.includes(s.label))
        );
        if (alreadyInPipeline) return;

        await tryAutoCreate(conversation);
      }

      // 2. Conversation Resolved (Auto-Win) Automation
      if (type === 'CHANGE_CONVERSATION_STATUS') {
        const { conversationId, status } = payload;
        if (status !== 'resolved' || !conversationId) return;

        // Skip if config is not loaded yet
        if (!config || !Array.isArray(config.pipelines)) return;

        const conversation =
          store.getters['conversations/getConversationById'](conversationId);
        if (!conversation) return;

        const currentLabels = [...(conversation.labels || [])];

        for (const pipeline of config.pipelines) {
          if (!pipeline.automations?.auto_win_on_resolve) continue;

          // Find current stage label active on conversation
          const allStagesLabels = pipeline.stages.map(s => s.label);
          const currentActiveLabel = currentLabels.find(lbl =>
            allStagesLabels.includes(lbl)
          );

          if (currentActiveLabel) {
            // Find target "Won" stage
            const wonStage = pipeline.stages.find(s => s.is_won);
            if (wonStage && currentActiveLabel !== wonStage.label) {
              // Strip all stages labels
              const cleanLabels = currentLabels.filter(
                lbl => !allStagesLabels.includes(lbl)
              );
              // Add Won stage label
              cleanLabels.push(wonStage.label);

              try {
                await store.dispatch('conversationLabels/update', {
                  conversationId,
                  labels: cleanLabels,
                });
              } catch (err) {
                console.error(
                  `Automation failed: auto_win_on_resolve for chat #${conversationId}`,
                  err
                );
              }
            }
          }
        }
      }
    });
  },
};
