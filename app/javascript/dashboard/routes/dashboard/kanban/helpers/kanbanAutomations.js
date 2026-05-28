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

    // Subscribe to store mutations
    return store.subscribe(async (mutation, state) => {
      const { type, payload } = mutation;

      // 1. New Conversation Created/Received Automation
      if (type === 'conversations/ADD_CONVERSATION') {
        const conversation = payload;
        if (!conversation || !conversation.id) return;
        
        // Skip if config is not loaded yet
        if (!config || !Array.isArray(config.pipelines)) return;

        for (const pipeline of config.pipelines) {
          if (!pipeline.automations?.auto_create) continue;

          // Check inbox filter
          const inboxFilter = pipeline.inboxes || [];
          if (inboxFilter.length > 0 && !inboxFilter.includes(conversation.inbox_id)) {
            continue;
          }

          // Check if conversation already has any of the stages' labels
          const stageLabels = pipeline.stages.map(s => s.label);
          const hasStageLabel = conversation.labels?.some(lbl => stageLabels.includes(lbl));
          
          if (!hasStageLabel && pipeline.stages.length > 0) {
            const firstStage = pipeline.stages[0];
            const currentLabels = [...(conversation.labels || [])];
            currentLabels.push(firstStage.label);

            try {
              await store.dispatch('conversationLabels/update', {
                conversationId: conversation.id,
                labels: currentLabels
              });
            } catch (err) {
              console.error(`Automation failed: auto_create for chat #${conversation.id}`, err);
            }
          }
        }
      }

      // 2. Conversation Resolved (Auto-Win) Automation
      if (type === 'conversations/CHANGE_CONVERSATION_STATUS') {
        const { conversationId, status } = payload;
        if (status !== 'resolved' || !conversationId) return;

        // Skip if config is not loaded yet
        if (!config || !Array.isArray(config.pipelines)) return;

        const conversation = store.getters['conversations/getConversationById'](conversationId);
        if (!conversation) return;

        const currentLabels = [...(conversation.labels || [])];

        for (const pipeline of config.pipelines) {
          if (!pipeline.automations?.auto_win_on_resolve) continue;

          // Find current stage label active on conversation
          const allStagesLabels = pipeline.stages.map(s => s.label);
          const currentActiveLabel = currentLabels.find(lbl => allStagesLabels.includes(lbl));

          if (currentActiveLabel) {
            // Find target "Won" stage
            const wonStage = pipeline.stages.find(s => s.is_won);
            if (wonStage && currentActiveLabel !== wonStage.label) {
              // Strip all stages labels
              const cleanLabels = currentLabels.filter(lbl => !allStagesLabels.includes(lbl));
              // Add Won stage label
              cleanLabels.push(wonStage.label);

              try {
                await store.dispatch('conversationLabels/update', {
                  conversationId,
                  labels: cleanLabels
                });
              } catch (err) {
                console.error(`Automation failed: auto_win_on_resolve for chat #${conversationId}`, err);
              }
            }
          }
        }
      }
    });
  }
};
