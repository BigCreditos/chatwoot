/* eslint-disable no-console, no-unused-vars, no-restricted-syntax, no-continue, no-await-in-loop */
import { KanbanConfigHelper } from './kanbanConfig';
import ConversationApi from 'dashboard/api/conversations';

export const KanbanAutomations = {
  register(store) {
    let config = null;
    let ready = false;

    const reloadConfig = async () => {
      try {
        const result = await KanbanConfigHelper.loadConfig(store);
        config = result.config;
        ready = true;
      } catch (err) {
        console.error('Failed to load Kanban config for automations:', err);
      }
    };

    reloadConfig();

    const tryAutoCreate = async conversation => {
      if (!conversation || !conversation.id) return;
      if (!config || !Array.isArray(config.pipelines)) return;

      for (const pipeline of config.pipelines) {
        if (!pipeline.automations?.auto_create) continue;

        const inboxFilter = pipeline.inboxes || [];
        if (inboxFilter.length > 0 && !inboxFilter.includes(conversation.inbox_id)) {
          continue;
        }

        const stageIds = pipeline.stages.map(s => s.id);
        const hasStage = conversation.kanban_stage && stageIds.includes(conversation.kanban_stage);

        if (!hasStage && pipeline.stages.length > 0) {
          const firstStage = pipeline.stages[0];

          try {
            await ConversationApi.update(conversation.id, {
              kanban_stage: firstStage.id,
            });
            store.dispatch('updateConversation', {
              id: conversation.id,
              kanban_stage: firstStage.id,
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

    return store.subscribe(async (mutation, state) => {
      const { type, payload } = mutation;

      if (type === 'ADD_CONVERSATION') {
        const conversation = payload;
        if (!conversation || !conversation.id) return;
        if (!config || !Array.isArray(config.pipelines)) return;
        if (conversation.status === 'resolved') return;

        const firstMsg = conversation.last_non_activity_message || conversation.messages?.[0];
        if (firstMsg && firstMsg.message_type === 1) return;

        await tryAutoCreate(conversation);
      }

      if (type === 'UPDATE_CONVERSATION') {
        const conversation = payload;
        if (!conversation || !conversation.id) return;
        if (!config || !Array.isArray(config.pipelines)) return;
        if (conversation.status !== 'open') return;

        const alreadyInPipeline = config.pipelines.some(p =>
          p.stages.some(s => s.id === conversation.kanban_stage)
        );
        if (alreadyInPipeline) return;

        await tryAutoCreate(conversation);
      }

      if (type === 'CHANGE_CONVERSATION_STATUS') {
        const { conversationId, status } = payload;
        if (status !== 'resolved' || !conversationId) return;

        if (!config || !Array.isArray(config.pipelines)) return;

        const conversation = store.getters['conversations/getConversationById'](conversationId);
        if (!conversation) return;

        for (const pipeline of config.pipelines) {
          if (!pipeline.automations?.auto_win_on_resolve) continue;

          const currentStageId = conversation.kanban_stage;
          if (!currentStageId) continue;

          const currentStage = pipeline.stages.find(s => s.id === currentStageId);
          if (!currentStage) continue;

          const wonStage = pipeline.stages.find(s => s.is_won);
          if (wonStage && currentStageId !== wonStage.id) {
            try {
              await ConversationApi.update(conversationId, {
                kanban_stage: wonStage.id,
              });
              store.dispatch('updateConversation', {
                id: conversationId,
                kanban_stage: wonStage.id,
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
    });
  },
};
